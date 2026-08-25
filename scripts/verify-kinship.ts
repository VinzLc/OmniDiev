/**
 * Vérifie les liens de parenté affirmés par le Codex.
 *
 * Une erreur de parenté ne s'attrape pas au motif : « Jenifael, fille de
 * Parandar » et « Camryn, fille de Sierra » ont la même forme, et seule la
 * seconde est fausse. Elle vient d'une note de chapitre isolée — « Fille de
 * Sierra » — que vingt-sept autres mentions contredisent en décrivant une
 * servante, mais qu'aucune règle syntaxique ne distingue.
 *
 * Chaque lien est donc soumis au modèle avec les mentions des DEUX personnes.
 * Contrôler une affirmation contre ses preuves est une tâche plus sûre que d'en
 * rédiger une : c'est ce déséquilibre qu'on exploite ici.
 *
 * Sortie : data/index/kin-rejected.json
 */
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import Anthropic from "@anthropic-ai/sdk";
import { loadEnv } from "../lib/env.ts";
import { credentials } from "../lib/credentials.ts";
import { loadCodex } from "../lib/codex.ts";
import { fold } from "../lib/text.ts";
import { pool } from "../lib/pool.ts";
import { askJson, withRetry, newSpend, dollars, CODEX_MODEL } from "../lib/claude.ts";

loadEnv();

const ROOT = path.resolve(import.meta.dirname, "..");
const CACHE = path.join(ROOT, "data", "codex-cache", "verdicts");
const OUT = path.join(ROOT, "data", "index", "kin-rejected.json");

const DRY = process.argv.includes("--dry-run");
const CONCURRENCY = 6;
const MAX_NOTES = 30;

const KIN = /\b(p[èe]re|m[èe]re|fils|fille|fr[èe]re|s(?:œ|oe)ur|[ée]pou[xs]e?|enfant|parent|a[îi]eul|petit[- ]fils|petite[- ]fille)\b/i;
const ARMES = /\b(?:fr[èe]res?|s(?:œ|oe)urs?)\s+d['’\s]\s*armes?\b/i;

const SCHEMA = {
  type: "object",
  properties: {
    lien: {
      type: "string",
      enum: ["parent", "enfant", "conjoint", "fratrie", "aucun"],
      description: "Ce que la seconde personne est pour la première. « aucun » s'il n'y a pas de parenté.",
    },
    nature: {
      type: "string",
      description: "biologique, adoptif, divin, par alliance… ou vide si les mentions ne le disent pas.",
    },
    raison: { type: "string", description: "Une phrase : la mention décisive, et ce que disent les autres." },
  },
  required: ["lien", "nature", "raison"],
  additionalProperties: false,
};

const SYSTEM = `Tu établis le lien de parenté réel entre deux personnages de l'œuvre d'Anne Robillard.

On te donne deux personnes, le lien qu'une encyclopédie leur prête, et les mentions relevées
pour chacune, chapitre par chapitre.

Ta réponse porte sur le LIEN, jamais sur la formulation. Si les mentions établissent une
filiation que l'encyclopédie qualifie mal — elle dit « père adoptif » là où le texte dit
« fils biologique » —, le lien existe : réponds « parent » ou « enfant », et corrige la
nature. Ne réponds « aucun » que s'il n'y a pas de parenté du tout.

« lien » dit ce que la SECONDE personne est pour la première :
- « parent »   : la seconde est le père, la mère, le parent adoptif ou divin de la première
- « enfant »   : la seconde est son fils, sa fille, son enfant adoptif ou divin
- « conjoint » : époux, épouse, compagne, compagnon
- « fratrie »  : frère ou sœur — jamais « frère d'armes »
- « aucun »    : aucune parenté

Réponds « aucun » quand :
- aucune mention n'énonce de parenté ;
- le lien relève de l'admiration, de la protection, du mentorat ou de la garde d'enfants ;
- le terme de parenté, dans la mention, désigne quelqu'un d'autre que ces deux personnes ;
- une note isolée énonce le lien mais le reste des mentions décrit la personne d'une façon
  qui l'exclut. Exemple : « Fille de Sierra » énoncé une fois, quand vingt-sept mentions
  décrivent une servante du palais de douze ans qui admire la commandante — on ne place pas
  l'enfant de la commandante en chef aux cuisines, et l'admiration ne fait pas une mère.
  Cette note isolée est une erreur de relevé.

Attention à ne pas confondre rareté et incompatibilité. « Sœur de Lavrenti » énoncé une
seule fois parmi trois cents mentions qui la disent commandante reste vrai : commander une
armée n'empêche pas d'avoir un frère. Seule l'incompatibilité disqualifie.

Dans le doute, réponds « aucun » : une encyclopédie muette vaut mieux qu'une fausse.`;

type Verdict = { lien: "parent" | "enfant" | "conjoint" | "fratrie" | "aucun"; nature: string; raison: string };
type Claim = { from: string; to: string; nature: string; key: string };

function notesByEntity() {
  const dir = path.join(ROOT, "data", "codex-cache", "chapters");
  const map = new Map<string, string[]>();
  for (const f of fs.readdirSync(dir)) {
    const d = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
    for (const e of d.entites ?? []) {
      const k = fold(e.nom ?? "");
      if (!k || !e.role) continue;
      const list = map.get(k);
      if (list) list.push(e.role); else map.set(k, [e.role]);
    }
  }
  return map;
}

/**
 * Mentions à soumettre : d'abord celles qui nomment l'autre personne.
 *
 * Un échantillon régulier ne suffit pas. Sierra compte 309 mentions dont quatre
 * seulement citent Lavrenti — celle qui dit « Sœur de Lavrenti » n'était pas
 * dans les trente retenues, et le contrôle a rejeté un lien parfaitement vrai.
 * Écarter un fait établi est plus grave que laisser passer l'erreur qu'on
 * cherche : la preuve décisive doit être montrée en premier.
 */
function evidence(list: string[], other: string, max: number) {
  const key = fold(other);
  const naming = list.filter((n) => fold(n).includes(key));
  const rest = list.filter((n) => !fold(n).includes(key));
  const room = Math.max(0, max - naming.length);
  const step = rest.length > room && room > 0 ? Math.ceil(rest.length / room) : 1;
  const filler = room > 0 ? rest.filter((_, i) => i % step === 0).slice(0, room) : [];
  return { shown: [...naming, ...filler], naming: naming.length };
}

function cached(key: string): Verdict | null {
  const p = path.join(CACHE, `${key}.json`);
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, "utf8")) as Verdict; } catch { return null; }
}

async function main() {
  const l = loadCodex();
  if (!l) { console.error("Codex absent."); process.exit(1); }

  const notes = notesByEntity();
  const claims: Claim[] = [];
  for (const e of l.codex.entries) {
    for (const r of e.relations) {
      if (!KIN.test(r.nature) || ARMES.test(r.nature)) continue;
      claims.push({
        from: e.name,
        to: r.name,
        nature: r.nature,
        // « v4 » : les contrôles précédents jugeaient la formulation et non le
        // lien, et rejetaient une filiation avérée pour un qualificatif inexact.
        key: createHash("sha1").update(`v4|${e.id}|${fold(r.name)}|${r.nature}`).digest("hex").slice(0, 12),
      });
    }
  }

  const todo = claims.filter((c) => !cached(c.key));
  console.log(`${claims.length} liens de parenté · ${claims.length - todo.length} déjà vérifiés · ${todo.length} à contrôler`);

  if (DRY) {
    const chars = todo.reduce((n, c) => {
      const a = evidence(notes.get(fold(c.from)) ?? [], c.to, MAX_NOTES).shown.join("").length;
      const b = evidence(notes.get(fold(c.to)) ?? [], c.from, MAX_NOTES).shown.join("").length;
      return n + a + b;
    }, 0);
    console.log(`\nÀ dépenser : ~${((chars / 3.6 / 1e6) * 1 + (todo.length * 120 / 1e6) * 5).toFixed(2)} $`);
    return;
  }

  if (todo.length) {
    if (!credentials().source) { console.error("Aucun identifiant Anthropic."); process.exit(1); }
    const client = new Anthropic();
    const spend = newSpend();
    fs.mkdirSync(CACHE, { recursive: true });

    await pool(todo, CONCURRENCY, async (c) => {
      const all = { from: notes.get(fold(c.from)) ?? [], to: notes.get(fold(c.to)) ?? [] };
      const a = evidence(all.from, c.to, MAX_NOTES);
      const b = evidence(all.to, c.from, MAX_NOTES);
      const mine = a.shown;
      const theirs = b.shown;
      const verdict = await withRetry(
        () => askJson<Verdict>(client, {
          system: SYSTEM,
          prompt:
            `LIEN AFFIRMÉ : ${c.from} → ${c.to} — « ${c.nature} »\n\n` +
            `DÉCOMPTE — ${c.from} : ${all.from.length} mentions, dont ${a.naming} citent ${c.to}. ` +
            `${c.to} : ${all.to.length} mentions, dont ${b.naming} citent ${c.from}.\n\n` +
            `MENTIONS DE ${c.from.toUpperCase()} (${mine.length} sur ${all.from.length}, ` +
            `dont ${a.naming} citant ${c.to}) :\n` +
            mine.map((n) => `- ${n}`).join("\n") +
            `\n\nMENTIONS DE ${c.to.toUpperCase()} (${theirs.length} sur ${all.to.length}, ` +
            `dont ${b.naming} citant ${c.from}) :\n` +
            (theirs.length ? theirs.map((n) => `- ${n}`).join("\n") : "- aucune mention relevée"),
          schema: SCHEMA,
          maxTokens: 400,
          spend,
          model: CODEX_MODEL,
        }),
        `${c.from} → ${c.to}`,
      );
      if (verdict) fs.writeFileSync(path.join(CACHE, `${c.key}.json`), JSON.stringify(verdict));
    }, (done, total) => {
      const w = 28, f = Math.round((done / total) * w);
      process.stdout.write(`\r  contrôle [${"█".repeat(f)}${"·".repeat(w - f)}] ${done}/${total}   `);
    });
    console.log(`\n  ${spend.calls} appels · ${dollars(spend).toFixed(2)} $`);
  }

  const rejected: { from: string; to: string; nature: string; raison: string }[] = [];
  const confirmed: { from: string; to: string; lien: string; nature: string }[] = [];
  let judged = 0;
  for (const c of claims) {
    const v = cached(c.key);
    if (!v) continue;
    judged++;
    if (v.lien === "aucun") rejected.push({ from: c.from, to: c.to, nature: c.nature, raison: v.raison });
    else confirmed.push({ from: c.from, to: c.to, lien: v.lien, nature: v.nature });
  }

  fs.writeFileSync(
    OUT,
    JSON.stringify({ builtAt: new Date().toISOString(), rejected, confirmed }, null, 1),
  );

  console.log(`\n${judged} liens jugés · ${rejected.length} écartés (${((rejected.length / judged) * 100).toFixed(0)} %) · ${confirmed.length} confirmés`);
  for (const r of rejected.slice(0, 10)) {
    console.log(`  ✗ ${r.from} → ${r.to} : ${r.raison.slice(0, 88)}`);
  }
  console.log(`\n→ ${path.relative(ROOT, OUT)}`);
}

main();
