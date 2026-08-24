/**
 * Le Codex : couche de synthèse construite hors ligne par `npm run codex`.
 *
 * Les fragments de texte répondent bien aux questions ponctuelles, mais mal aux
 * questions transversales — « Qui est Onyx ? », « Comment évolue Kira ? » —
 * parce que la réponse n'est écrite nulle part en un seul endroit : elle est
 * répartie sur douze tomes. Le Codex la précalcule sous forme de fiches.
 *
 * Il reste facultatif : sans lui, l'application fonctionne en recherche seule.
 */
import fs from "node:fs";
import path from "node:path";
import { fold, tokenize } from "./text.ts";
import { bookAt, bookLabel } from "./books.ts";
import { buildBm25, searchBm25, type Bm25Index } from "./bm25.ts";

export type EntityKind = "personnage" | "lieu" | "peuple" | "objet" | "concept" | "événement";

export type CodexEntry = {
  id: string;
  kind: EntityKind;
  name: string;
  aliases: string[];
  /** Une phrase, pour situer immédiatement. */
  gloss: string;
  description: string;
  /** Évolution à travers la saga. */
  arc: string;
  relations: { name: string; nature: string }[];
  /** Positions absolues des tomes où l'entité apparaît (1 à 24), ordonnées. */
  books: number[];
  firstSeen: string;
};

export type ChapterSummary = {
  /** Position absolue du tome. */
  book: number;
  chapter: number;
  label: string;
  pageStart: number;
  summary: string;
};

export type Codex = {
  builtAt: string;
  model: string;
  entries: CodexEntry[];
  chapters: ChapterSummary[];
  /** Résumé par tome, assemblé à partir des chapitres. Clé : position absolue. */
  synopses: { book: number; synopsis: string }[];
};

export type CodexHit = { entry: CodexEntry; score: number; exact: boolean };

type Loaded = {
  codex: Codex;
  bm25: Bm25Index;
  /** Nom ou alias replié → index de l'entrée. */
  byName: Map<string, number>;
};

/**
 * Mots de fonction récurrents dans la saga, qui ne peuvent pas servir seuls
 * d'alias : ils désignent des dizaines de personnages.
 */
const ROLE_WORDS = new Set(`
roi reine prince princesse empereur imperatrice chevalier chevaliers ecuyer
sorcier sorciere magicien magicienne immortel immortels dieu deesse dieux
seigneur dame maitre maitresse guerrier guerriere capitaine soldat soldats
commandant chef general gouverneur monarque souverain souveraine heros heroine
homme femme enfant fille garcon fils frere soeur pere mere ancien ancienne
le la les un une de du des et d l a au aux
`.trim().split(/\s+/));

/**
 * Un alias n'est retenu que s'il identifie l'entité à lui seul.
 *
 * La rédaction des fiches produit parfois des désignations génériques —
 * « Onyx, aussi appelé Sorcier, Magicien ». Indexées telles quelles, elles
 * feraient remonter la fiche d'Onyx sur toute question mentionnant un sorcier,
 * y compris celles qui portent sur Asbeth. On écarte donc les alias entièrement
 * composés de mots de fonction : « Empereur Noir » passe (« noir » est
 * distinctif), « Sorcier » ne passe pas.
 */
function aliasIsDistinctive(alias: string): boolean {
  const words = fold(alias).split(" ").filter(Boolean);
  if (!words.length) return false;
  // Trois lettres suffisent : « Fan » est un vrai nom. Les formes courtes sans
  // valeur (« les », « roi ») sont déjà écartées par ROLE_WORDS.
  if (fold(alias).replace(/ /g, "").length < 3) return false;
  return words.some((w) => !ROLE_WORDS.has(w));
}

const CODEX_PATH = () => path.join(process.cwd(), "data", "index", "codex.json");

let loaded: Loaded | null | undefined;

export function loadCodex(): Loaded | null {
  if (loaded !== undefined) return loaded;
  const p = CODEX_PATH();
  if (!fs.existsSync(p)) return (loaded = null);

  const codex: Codex = JSON.parse(fs.readFileSync(p, "utf8"));
  // Le filtrage a lieu au chargement, pas à la construction : corriger un alias
  // douteux ne doit pas obliger à reconstruire le Codex.
  for (const e of codex.entries) e.aliases = e.aliases.filter(aliasIsDistinctive);

  const docs = codex.entries.map(entryText);
  const byName = new Map<string, number>();
  codex.entries.forEach((e, i) => {
    for (const n of [e.name, ...e.aliases]) {
      const k = fold(n);
      if (k.length >= 3 && !byName.has(k)) byName.set(k, i);
    }
  });
  return (loaded = { codex, bm25: buildBm25(docs), byName });
}

export function entryText(e: CodexEntry): string {
  const rel = e.relations.map((r) => `${r.name} (${r.nature})`).join(", ");
  return [
    `${e.name} — ${e.kind}`,
    e.aliases.length ? `Aussi appelé : ${e.aliases.join(", ")}` : "",
    e.gloss,
    e.description,
    e.arc ? `Évolution : ${e.arc}` : "",
    rel ? `Liens : ${rel}` : "",
    `Tomes : ${e.books.map((o) => bookLabel(bookAt(o))).join(" · ")}`,
  ].filter(Boolean).join("\n");
}

/**
 * Cherche les fiches pertinentes.
 *
 * La correspondance exacte sur un nom prime toujours : si la question contient
 * « Amecareth », la fiche d'Amecareth doit remonter, quel que soit le reste.
 */
export function searchCodex(query: string, limit = 4, maxOrder?: number): CodexHit[] {
  const l = loadCodex();
  if (!l) return [];

  const hits = new Map<number, CodexHit>();
  const q = fold(query);
  const words = q.split(" ").filter(Boolean);

  for (const [name, idx] of l.byName) {
    // Frontières de mot : « ki » ne doit pas déclencher la fiche de « Kira ».
    if (new RegExp(`(^| )${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}( |$)`).test(q)) {
      hits.set(idx, { entry: l.codex.entries[idx], score: 100 + name.length, exact: true });
      continue;
    }
    // Un nom propre mal orthographié reste un nom propre : « Farell » pour
    // « Farrell » ne doit pas faire retomber la recherche sur le sens des mots,
    // qui ramènerait n'importe quel personnage décrit comme « compagne ».
    if (!name.includes(" ") && name.length >= 5) {
      if (words.some((w) => Math.abs(w.length - name.length) <= 1 && editDistance1(w, name))) {
        hits.set(idx, { entry: l.codex.entries[idx], score: 90 + name.length, exact: true });
      }
    }
  }

  for (const { doc, score } of searchBm25(l.bm25, query, limit * 3)) {
    if (!hits.has(doc)) hits.set(doc, { entry: l.codex.entries[doc], score, exact: false });
  }

  let out = [...hits.values()].sort((a, b) => b.score - a.score);
  if (maxOrder) out = out.filter((h) => h.entry.books.some((o) => o <= maxOrder));
  return out.slice(0, limit);
}


/** Vrai si `a` et `b` sont à une insertion, suppression ou substitution près. */
function editDistance1(a: string, b: string): boolean {
  if (a === b) return false; // l'égalité est traitée par la voie exacte
  const [s, l] = a.length <= b.length ? [a, b] : [b, a];
  if (l.length - s.length > 1) return false;

  let i = 0;
  while (i < s.length && s[i] === l[i]) i++;
  if (i === s.length) return l.length === s.length + 1; // suffixe en trop

  if (s.length === l.length) {
    // Substitution : le reste doit coïncider.
    return s.slice(i + 1) === l.slice(i + 1);
  }
  return s.slice(i) === l.slice(i + 1); // insertion dans le plus long
}

/**
 * Fiches des entités qui dominent les passages retrouvés.
 *
 * Choisir les fiches d'après la seule question laisse un angle mort : à
 * « Qui était la compagne de Farrell ? », la recherche ramène dix-neuf mentions
 * de Swan sans que sa fiche soit jamais fournie — et le modèle, privé de la
 * ligne « Princesse d'Opale », lui invente une origine. Les extraits disent donc
 * eux-mêmes de qui il faut fournir l'identité.
 */
export function codexForPassages(texts: string[], limit = 4, maxOrder?: number): CodexHit[] {
  const l = loadCodex();
  if (!l || !texts.length) return [];

  const folded = texts.map((t) => ` ${fold(t)} `);
  const counts = new Map<number, number>();

  for (const [name, idx] of l.byName) {
    if (name.length < 4) continue;
    const needle = ` ${name} `;
    let n = 0;
    for (const t of folded) {
      let from = 0;
      for (;;) {
        const at = t.indexOf(needle, from);
        if (at < 0) break;
        n++;
        from = at + 1;
      }
    }
    if (n) counts.set(idx, (counts.get(idx) ?? 0) + n);
  }

  let out = [...counts]
    .sort((a, b) => b[1] - a[1])
    .map(([idx, n]) => ({ entry: l.codex.entries[idx], score: n, exact: false }));
  if (maxOrder) out = out.filter((h) => h.entry.books.some((o) => o <= maxOrder));
  return out.slice(0, limit);
}

/** Réunit les fiches issues de la question et celles issues des extraits. */
export function mergeCodexHits(fromQuery: CodexHit[], fromPassages: CodexHit[], limit = 6): CodexHit[] {
  const seen = new Set<string>();
  const out: CodexHit[] = [];
  // Les correspondances exactes de la question passent en premier : c'est
  // l'entité sur laquelle porte explicitement la demande.
  for (const h of [...fromQuery.filter((h) => h.exact), ...fromPassages, ...fromQuery.filter((h) => !h.exact)]) {
    if (seen.has(h.entry.id)) continue;
    seen.add(h.entry.id);
    out.push(h);
    if (out.length >= limit) break;
  }
  return out;
}

/** Alias des entités citées, pour élargir la requête de recherche. */
export function expandQuery(query: string): string {
  const l = loadCodex();
  if (!l) return query;
  const extra: string[] = [];
  for (const h of searchCodex(query, 3)) {
    if (!h.exact) continue;
    extra.push(...h.entry.aliases.slice(0, 3));
  }
  return extra.length ? `${query} ${extra.join(" ")}` : query;
}

export function codexStats() {
  const l = loadCodex();
  if (!l) return null;
  const byKind: Record<string, number> = {};
  for (const e of l.codex.entries) byKind[e.kind] = (byKind[e.kind] ?? 0) + 1;
  return {
    builtAt: l.codex.builtAt,
    entries: l.codex.entries.length,
    chapters: l.codex.chapters.length,
    byKind,
  };
}

/** Synopsis d'un tome, désigné par sa position absolue. */
export function synopsisFor(order: number): string | null {
  const l = loadCodex();
  return l?.codex.synopses.find((s) => s.book === order)?.synopsis ?? null;
}

export { tokenize };
