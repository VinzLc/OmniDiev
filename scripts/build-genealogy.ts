/**
 * Construit les arbres généalogiques à partir du Codex.
 *
 * Les relations du Codex décrivent la parenté en prose — « son fils dieu-dragon »,
 * « père biologique, le ressuscite ». Une expression régulière y suffirait presque,
 * mais pas tout à fait : « Itzaman — retrouve son fils captif » ferait d'Itzaman
 * l'enfant d'Onyx, et « frère d'armes » n'est pas une fratrie. Un arbre affirme
 * des faits ; on demande donc au modèle de trancher, à partir des relations déjà
 * calculées et sans relire les romans.
 *
 * Sortie : data/index/genealogy.json
 */
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import Anthropic from "@anthropic-ai/sdk";
import { loadEnv } from "../lib/env.ts";
import { credentials } from "../lib/credentials.ts";
import { loadCodex, type CodexEntry } from "../lib/codex.ts";
import { fold } from "../lib/text.ts";
import { pool } from "../lib/pool.ts";
import { askJson, withRetry, newSpend, dollars, CODEX_MODEL } from "../lib/claude.ts";

loadEnv();

const ROOT = path.resolve(import.meta.dirname, "..");
const CACHE = path.join(ROOT, "data", "codex-cache", "kin");
const OUT = path.join(ROOT, "data", "index", "genealogy.json");

const DRY = process.argv.includes("--dry-run");
const MODEL = CODEX_MODEL;
const CONCURRENCY = 6;
/** En deçà, un « arbre » n'est qu'un couple isolé. */
const MIN_MEMBERS = 3;

const ARMES = /\b(?:fr[èe]res?|s(?:œ|oe)urs?)\s+d['’\s]\s*armes?\b/i;
const KIN =
  /\b(p[èe]re|m[èe]re|fils|fille|fr[èe]re|s(?:œ|oe)ur|[ée]pou[xs]e?|mari[ée]?|femme de|conjoint|enfant|parent|anc[êe]tre|descendant|petit[- ]fils|petite[- ]fille|oncle|tante|neveu|ni[èe]ce|a[îi]eul)\b/i;

type Link = { nom: string; nature?: string };
type Kin = { parents: Link[]; enfants: Link[]; conjoints: Link[]; fratrie: Link[] };

const SCHEMA = {
  type: "object",
  properties: {
    parents: linkArray("Qui a engendré ou élevé cette personne."),
    enfants: linkArray("Qui cette personne a engendré ou élevé."),
    conjoints: linkArray("Époux, épouse, compagne ou compagnon."),
    fratrie: linkArray("Frères et sœurs — jamais les frères d'armes."),
  },
  required: ["parents", "enfants", "conjoints", "fratrie"],
  additionalProperties: false,
};

function linkArray(description: string) {
  return {
    type: "array",
    description,
    items: {
      type: "object",
      properties: {
        nom: { type: "string" },
        nature: { type: "string", description: "biologique, adoptif, divin… si le texte le précise." },
      },
      required: ["nom"],
      additionalProperties: false,
    },
  };
}

const SYSTEM = `Tu établis la parenté d'un personnage de l'œuvre d'Anne Robillard, à partir de relations déjà relevées.

Ne retiens QUE les liens de sang, d'adoption ou d'alliance explicitement énoncés :
- parents, enfants, conjoints, frères et sœurs ;
- l'adoption et la filiation divine comptent — précise-le dans « nature ».

N'invente aucun lien. Écarte impitoyablement :
- « frère d'armes », « sœur d'armes » : ce sont des compagnons de combat, pas une fratrie ;
- les mentions où le terme de parenté désigne quelqu'un d'autre que les deux personnes
  citées — « retrouve son fils captif » ne fait pas de l'allié un enfant ;
- mentor, tuteur, protecteur, maître : ce ne sont pas des parents.

Chaque nom doit apparaître tel quel dans les relations fournies. Dans le doute, omets.`;

function signals(entries: CodexEntry[]) {
  const byName = new Map<string, CodexEntry>();
  for (const e of entries) {
    byName.set(fold(e.name), e);
    for (const a of e.aliases) if (!byName.has(fold(a))) byName.set(fold(a), e);
  }

  /** Relations mentionnant l'entité, dans les deux sens. */
  const around = new Map<string, { from: string; to: string; nature: string }[]>();
  const note = (id: string, r: { from: string; to: string; nature: string }) => {
    const list = around.get(id);
    if (list) list.push(r);
    else around.set(id, [r]);
  };

  for (const e of entries) {
    for (const r of e.relations) {
      if (!KIN.test(r.nature) || ARMES.test(r.nature)) continue;
      const rec = { from: e.name, to: r.name, nature: r.nature };
      note(e.id, rec);
      const target = byName.get(fold(r.name));
      if (target && target.id !== e.id) note(target.id, rec);
    }
  }
  return { around, byName };
}

function cached(key: string): Kin | null {
  const p = path.join(CACHE, `${key}.json`);
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, "utf8")) as Kin; } catch { return null; }
}

async function main() {
  const l = loadCodex();
  if (!l) {
    console.error("Codex absent. Lancez d'abord : npm run codex");
    process.exit(1);
  }
  const entries = l.codex.entries;
  const { around, byName } = signals(entries);

  const targets = entries.filter((e) => around.has(e.id));
  console.log(`${targets.length} entités portent un signal de parenté, sur ${entries.length}`);

  const key = (e: CodexEntry) =>
    `${e.id}.${createHash("sha1").update(JSON.stringify(around.get(e.id))).digest("hex").slice(0, 10)}`;

  const todo = targets.filter((e) => !cached(key(e)));
  console.log(`${targets.length - todo.length} en cache, ${todo.length} à établir`);

  if (DRY) {
    const chars = todo.reduce((n, e) => n + JSON.stringify(around.get(e.id)).length, 0);
    console.log(`\nÀ dépenser : ~${((chars / 3.6 / 1e6) * 1 + (todo.length * 200 / 1e6) * 5).toFixed(2)} $`);
    return;
  }

  if (todo.length) {
    const cred = credentials();
    if (!cred.source) {
      console.error("Aucun identifiant Anthropic.");
      process.exit(1);
    }
    const client = new Anthropic();
    const spend = newSpend();
    fs.mkdirSync(CACHE, { recursive: true });

    await pool(todo, CONCURRENCY, async (e) => {
      const lines = (around.get(e.id) ?? [])
        .map((r) => `- ${r.from} → ${r.to} : ${r.nature}`)
        .join("\n");
      const kin = await withRetry(
        () => askJson<Kin>(client, {
          system: SYSTEM,
          prompt: `PERSONNAGE : ${e.name}\n${e.gloss}\n\nRELATIONS RELEVÉES :\n${lines}`,
          schema: SCHEMA,
          maxTokens: 1200,
          spend,
          model: MODEL,
        }),
        `parenté ${e.name}`,
      );
      if (kin) fs.writeFileSync(path.join(CACHE, `${key(e)}.json`), JSON.stringify(kin));
    }, (done, total) => {
      const w = 28, f = Math.round((done / total) * w);
      process.stdout.write(`\r  parenté [${"█".repeat(f)}${"·".repeat(w - f)}] ${done}/${total}   `);
    });
    console.log(`\n  ${spend.calls} appels · ${dollars(spend).toFixed(2)} $`);
  }

  // ── Assemblage du graphe ────────────────────────────────────────────────
  const entryById = new Map(entries.map((e) => [e.id, e]));

  /**
   * Seules des personnes ont une parenté.
   * Sans ce filtre, « Shola » — un royaume — se retrouvait parmi les parents de
   * Kira, parce que la prose dit « la reine de Shola, sa mère ».
   */
  const isPerson = (id: string) => entryById.get(id)?.kind === "personnage";

  /*
   * Fiches en double, réunies sous une seule identité.
   *
   * Le Codex les signale lui-même : le nom d'une fiche figure parmi les alias
   * d'une autre — « Napashni » est un alias de « Napalhuaca », « Nomar » l'est
   * d'« Akuretari ». Deux fiches pour une personne donneraient deux parents là
   * où il n'y en a qu'un. La plus étoffée l'emporte ; à égalité, l'ordre
   * alphabétique tranche, pour que le résultat ne dépende pas du hasard.
   */
  const canonical = new Map<string, string>();
  {
    const aliasOwners = new Map<string, CodexEntry[]>();
    for (const e of entries) {
      for (const a of e.aliases) {
        const k = fold(a);
        const list = aliasOwners.get(k);
        if (list) list.push(e); else aliasOwners.set(k, [e]);
      }
    }
    for (const e of entries) {
      const owners = (aliasOwners.get(fold(e.name)) ?? []).filter((o) => o.id !== e.id);
      if (!owners.length) continue;
      const best = owners.sort(
        (a, b) => b.books.length - a.books.length || a.id.localeCompare(b.id),
      )[0];
      const winner =
        best.books.length > e.books.length ||
        (best.books.length === e.books.length && best.id < e.id)
          ? best.id
          : e.id;
      if (winner !== e.id) canonical.set(e.id, winner);
    }
    // Chaînes A→B→C : on remonte jusqu'au bout, sans boucler.
    for (const [from] of canonical) {
      const seen = new Set([from]);
      let to = canonical.get(from)!;
      while (canonical.has(to) && !seen.has(to)) { seen.add(to); to = canonical.get(to)!; }
      canonical.set(from, to);
    }
    if (canonical.size) console.log(`  ${canonical.size} fiches en double réunies`);
  }

  const canon = (id: string) => canonical.get(id) ?? id;
  const resolve = (name: string) => {
    const found = byName.get(fold(name))?.id ?? null;
    if (!found) return null;
    const id = canon(found);
    return isPerson(id) ? id : null;
  };

  /**
   * Une arête déclarée par l'enfant lui-même l'emporte sur celle déduite de la
   * fiche du parent : c'est sur sa propre fiche que la filiation est la mieux
   * établie. Cette distinction sert à trancher les contradictions.
   */
  type Edge = { child: string; parent: string; self: boolean; nature?: string };
  const edges: Edge[] = [];
  const spouses = new Map<string, Set<string>>();
  const addSpouse = (a: string, b: string) => {
    const s = spouses.get(a);
    if (s) s.add(b); else spouses.set(a, new Set([b]));
  };

  for (const e of targets) {
    const kin = cached(key(e));
    if (!kin || !isPerson(canon(e.id))) continue;
    const me = canon(e.id);
    for (const p of kin.parents ?? []) {
      const id = resolve(p.nom);
      if (id && id !== me) edges.push({ child: me, parent: id, self: true, nature: p.nature });
    }
    for (const c of kin.enfants ?? []) {
      const id = resolve(c.nom);
      if (id && id !== me) edges.push({ child: id, parent: me, self: false, nature: c.nature });
    }
    for (const sp of kin.conjoints ?? []) {
      const id = resolve(sp.nom);
      if (id && id !== me) { addSpouse(me, id); addSpouse(id, me); }
    }
  }

  // Poids d'une filiation : combien de déclarations la soutiennent, et
  // l'enfant lui-même en fait-il partie.
  const weight = new Map<string, { n: number; self: boolean; nature?: string }>();
  for (const e of edges) {
    const k = `${e.parent}>${e.child}`;
    const cur = weight.get(k) ?? { n: 0, self: false, nature: e.nature };
    weight.set(k, { n: cur.n + 1, self: cur.self || e.self, nature: cur.nature ?? e.nature });
  }

  /*
   * Contradictions de sens.
   *
   * Quand A est déclaré parent de B et B parent de A, l'une des deux lectures
   * est fausse — c'est ainsi que Maximilien, fils adoptif d'Onyx, se retrouvait
   * aussi son père. On tranche par la déclaration de l'intéressé ; à égalité de
   * force, on écarte les deux plutôt que d'inventer une génération.
   */
  const parents = new Map<string, Set<string>>();
  const kinds = new Map<string, string>();
  let dropped = 0;
  for (const [k, w] of weight) {
    const [parent, child] = k.split(">");
    const reverse = weight.get(`${child}>${parent}`);
    if (reverse) {
      const stronger = w.self !== reverse.self ? w.self : w.n > reverse.n;
      const equal = w.self === reverse.self && w.n === reverse.n;
      if (equal) { dropped++; continue; }
      if (!stronger) continue;
    }
    const set = parents.get(child);
    if (set) set.add(parent); else parents.set(child, new Set([parent]));
    if (w.nature) kinds.set(k, w.nature);
  }
  if (dropped) console.log(`  ${dropped / 2} filiations contradictoires écartées`);

  // ── Arbres centrés sur une personne ─────────────────────────────────────
  /*
   * Pas de « familles » au sens des composantes connexes : de proche en proche,
   * les alliances relient 173 personnages sur vingt-neuf générations, ce qui ne
   * s'affiche ni ne se lit. Chaque arbre est donc centré sur quelqu'un et borné
   * à deux générations de part et d'autre — ce qu'on cherche vraiment quand on
   * consulte une généalogie.
   */
  const childrenOf = new Map<string, string[]>();
  for (const [child, ps] of parents) {
    for (const p of ps) {
      const list = childrenOf.get(p);
      if (list) list.push(child); else childrenOf.set(p, [child]);
    }
  }

  /**
   * Fratrie : les autres enfants d'un même parent.
   *
   * Avec des ascendances divines partagées, ce calcul rendait Nemeroff à la fois
   * fils et frère d'Onyx. Un lien plus proche l'emporte toujours : qui est déjà
   * parent, enfant ou conjoint ne peut pas être aussi frère ou sœur.
   */
  const siblingsOf = (id: string) => {
    const closer = new Set<string>([
      ...(parents.get(id) ?? []),
      ...(childrenOf.get(id) ?? []),
      ...(spouses.get(id) ?? []),
    ]);
    const out = new Set<string>();
    for (const p of parents.get(id) ?? []) {
      for (const c of childrenOf.get(p) ?? []) {
        if (c !== id && !closer.has(c)) out.add(c);
      }
    }
    return [...out];
  };

  const people: Record<string, {
    name: string; parents: string[]; children: string[]; spouses: string[]; siblings: string[];
  }> = {};
  const involved = new Set<string>([...parents.keys(), ...childrenOf.keys(), ...spouses.keys()]);
  for (const id of involved) {
    if (!isPerson(id)) continue;
    people[id] = {
      name: entryById.get(id)?.name ?? id,
      parents: [...(parents.get(id) ?? [])],
      children: childrenOf.get(id) ?? [],
      spouses: [...(spouses.get(id) ?? [])],
      siblings: siblingsOf(id),
    };
  }

  /** Membres de l'arbre centré sur `id` : deux générations de part et d'autre. */
  const treeMembers = (id: string) => {
    const out = new Set<string>([id]);
    const up = (x: string, d: number) => {
      if (d === 0) return;
      for (const p of people[x]?.parents ?? []) { out.add(p); up(p, d - 1); }
    };
    const down = (x: string, d: number) => {
      if (d === 0) return;
      for (const c of people[x]?.children ?? []) { out.add(c); down(c, d - 1); }
    };
    up(id, 2);
    down(id, 2);
    for (const s of people[id]?.spouses ?? []) out.add(s);
    for (const s of people[id]?.siblings ?? []) out.add(s);
    return [...out];
  };

  const trees = Object.keys(people)
    .map((id) => ({
      id,
      name: people[id].name,
      members: treeMembers(id),
      books: entryById.get(id)?.books.length ?? 0,
    }))
    .filter((t) => t.members.length >= MIN_MEMBERS)
    .map((t) => ({ id: t.id, name: t.name, size: t.members.length, books: t.books, members: t.members }))
    .sort((a, b) => b.size - a.size || b.books - a.books);

  fs.writeFileSync(
    OUT,
    JSON.stringify({
      builtAt: new Date().toISOString(),
      model: MODEL,
      people,
      trees: trees.map(({ id, name, size, books }) => ({ id, name, size, books })),
      kinds: Object.fromEntries(kinds),
    }),
  );

  const named = trees;
  console.log(`\n${named.length} arbres d'au moins ${MIN_MEMBERS} personnes`);
  for (const f of named.slice(0, 8)) console.log(`  ${String(f.size).padStart(3)} personnes — ${f.name}`);
  console.log(`\n→ ${path.relative(ROOT, OUT)}`);
}

main();
