/**
 * Construit le Codex : la couche de synthèse qui manque à la recherche seule.
 *
 * Trois passes, chacune reprenant là où la précédente s'est arrêtée :
 *
 *   1. Chapitres — un résumé et la liste des entités citées, pour ~600 chapitres.
 *   2. Fiches    — agrégation de toutes les mentions d'une entité en une fiche
 *                  cohérente : rôle, évolution, liens, tomes d'apparition.
 *   3. Synopsis  — un résumé par tome, assemblé depuis les résumés de chapitre.
 *
 * Tout résultat intermédiaire est écrit dans data/codex-cache/. Une exécution
 * interrompue reprend sans repayer ce qui est déjà calculé.
 *
 * Usage :
 *   npm run codex                      construit tout
 *   npm run codex -- --dry-run         estime le coût sans appeler l'API
 *   npm run codex -- --tomes 1,2       se limite à certains tomes
 *   npm run codex -- --min-chapters 5  relève le seuil d'entrée d'une entité
 */
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import Anthropic from "@anthropic-ai/sdk";
import { loadEnv } from "../lib/env.ts";
import { credentials } from "../lib/credentials.ts";
import { BOOKS, SAGAS, ROMAN, bookAt, bookId, bookLabel, sagaOf } from "../lib/books.ts";
import { parseBook, collectVocab } from "../lib/parse.ts";
import { buildDictionary, repairText } from "../lib/ocr-repair.ts";
import { fold } from "../lib/text.ts";
import { loadRejections, rejectionsFor, type Rejection } from "../lib/corrections.ts";
import { pool } from "../lib/pool.ts";
import { askJson, withRetry, newSpend, dollars, CODEX_MODEL, type Spend } from "../lib/claude.ts";
import type { Codex, CodexEntry, ChapterSummary, EntityKind } from "../lib/codex.ts";

loadEnv();

const ROOT = path.resolve(import.meta.dirname, "..");
const CACHE = path.join(ROOT, "data", "codex-cache");
const OUT = path.join(ROOT, "data", "index");

const KINDS: EntityKind[] = ["personnage", "lieu", "peuple", "objet", "concept", "événement"];
const CONCURRENCY = 6;
const MAX_CHAPTER_CHARS = 26000;

// ── Arguments ─────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
const flag = (name: string) => argv.includes(`--${name}`);
const value = (name: string) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
};

const DRY = flag("dry-run");
/** `--saga 2` restreint à une épopée ; `--books 1,2` à des positions absolues. */
const ONLY_SAGA = value("saga") ? Number(value("saga")) : null;
const ONLY_BOOKS = value("books")?.split(",").map(Number).filter(Boolean);
const MIN_CHAPTERS = Number(value("min-chapters") ?? 3);
const MODEL = value("model") ?? CODEX_MODEL;

// ── Utilitaires de cache ──────────────────────────────────────────────────

const cacheDir = (sub: string) => {
  const d = path.join(CACHE, sub);
  fs.mkdirSync(d, { recursive: true });
  return d;
};

function cached<T>(sub: string, key: string): T | null {
  const p = path.join(cacheDir(sub), `${key}.json`);
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, "utf8")) as T; } catch { return null; }
}

function store(sub: string, key: string, data: unknown) {
  fs.writeFileSync(path.join(cacheDir(sub), `${key}.json`), JSON.stringify(data));
}

const progress = (label: string) => (done: number, total: number) => {
  const w = 28;
  const f = Math.round((done / total) * w);
  process.stdout.write(`\r  ${label} [${"█".repeat(f)}${"·".repeat(w - f)}] ${done}/${total}   `);
};

// ── Lecture du texte des tomes ────────────────────────────────────────────

/** `order` est la position absolue du tome, seule clé utilisée en aval. */
type ChapterText = { order: number; chapter: number; label: string; page: number; text: string };

function readChapters(): ChapterText[] {
  const raws = new Map<number, string>();
  for (const b of BOOKS) {
    const p = path.join(ROOT, "data", "raw", `${bookId(b)}.txt`);
    if (!fs.existsSync(p)) {
      console.error(`Texte brut absent (${path.relative(ROOT, p)}). Lancez : npm run extract`);
      process.exit(1);
    }
    raws.set(b.order, fs.readFileSync(p, "utf8"));
  }

  // Le pipeline doit être identique à celui de build-corpus, sans quoi les
  // résumés porteraient sur un découpage en chapitres différent de l'index.
  const dict = buildDictionary(
    collectVocab(BOOKS.filter((b) => b.quality === "clean").map((b) => raws.get(b.order)!)),
  );
  for (const b of BOOKS) {
    if (b.quality === "scan") raws.set(b.order, repairText(raws.get(b.order)!, dict).text);
  }
  const vocab = collectVocab([...raws.values()]);

  const out: ChapterText[] = [];
  for (const b of BOOKS) {
    if (ONLY_SAGA && b.saga !== ONLY_SAGA) continue;
    if (ONLY_BOOKS && !ONLY_BOOKS.includes(b.order)) continue;
    const parsed = parseBook(b, raws.get(b.order)!, vocab);

    if (parsed.chapters.length) {
      parsed.chapters.forEach((ch, i) => {
        const paras = parsed.paragraphs.filter((p) => p.chapter === i);
        if (!paras.length) return;
        out.push({
          order: b.order,
          chapter: i,
          label: ch.label,
          page: paras[0].page,
          text: paras.map((p) => p.text).join("\n\n").slice(0, MAX_CHAPTER_CHARS),
        });
      });
      continue;
    }

    // Livre sans découpage — ses titres de chapitre sont incrustés en image et
    // n'existent pas dans la couche texte. Sans ce repli, il sortirait indexé
    // pour la recherche mais absent du Codex : aucun résumé, aucun synopsis, et
    // ses personnages ne pèseraient sur aucune fiche. On le tranche donc en
    // segments de lecture, désignés par leurs pages puisqu'ils n'ont pas de nom.
    let buf: typeof parsed.paragraphs = [];
    let len = 0;
    let seg = 0;
    const emit = () => {
      if (!buf.length) return;
      out.push({
        order: b.order,
        chapter: seg++,
        label: `Pages ${buf[0].page} à ${buf[buf.length - 1].page}`,
        page: buf[0].page,
        text: buf.map((p) => p.text).join("\n\n"),
      });
      buf = [];
      len = 0;
    };
    for (const para of parsed.paragraphs) {
      buf.push(para);
      len += para.text.length;
      if (len >= MAX_CHAPTER_CHARS) emit();
    }
    emit();
  }
  return out;
}

// ── Passe 1 : résumés de chapitre ─────────────────────────────────────────

type Mention = { nom: string; type: EntityKind; role: string };
type Digest = { resume: string; entites: Mention[] };

const DIGEST_SCHEMA = {
  type: "object",
  properties: {
    resume: { type: "string", description: "3 à 5 phrases : ce qui se passe, et ce que cela change." },
    entites: {
      type: "array",
      items: {
        type: "object",
        properties: {
          nom: { type: "string" },
          type: { type: "string", enum: KINDS },
          role: { type: "string", description: "Ce que cette entité fait ou subit dans CE chapitre." },
        },
        required: ["nom", "type", "role"],
        additionalProperties: false,
      },
    },
  },
  required: ["resume", "entites"],
  additionalProperties: false,
};

const DIGEST_SYSTEM = `Tu dépouilles « Les Chevaliers d'Émeraude » d'Anne Robillard pour en constituer une encyclopédie.

Pour le chapitre fourni, produis :
- un résumé de 3 à 5 phrases : les faits, les décisions, les révélations. Pas de commentaire littéraire.
- la liste des entités marquantes, avec le rôle précis de chacune DANS CE CHAPITRE.

Consignes :
- Emploie les noms tels qu'ils apparaissent dans le texte, sans titre ni royaume ajouté : « Wellan », pas « Wellan d'Émeraude ».
- Ne retiens que ce qui compte : dix entités au maximum, souvent moins.
- N'invente rien. Si un point est ambigu dans le texte, ne le tranche pas.`;

async function pass1(client: Anthropic, chapters: ChapterText[], spend: Spend) {
  const todo = chapters.filter((c) => !cached(`chapters`, key(c)));
  console.log(`\nPasse 1 — résumés de chapitre : ${chapters.length} au total, ${todo.length} à calculer`);
  if (!todo.length) return;

  await pool(todo, CONCURRENCY, async (c) => {
    const d = await withRetry(
      () => askJson<Digest>(client, {
        system: DIGEST_SYSTEM,
        prompt: `${bookLabel(bookAt(c.order))}\n${c.label}\n\n${c.text}`,
        schema: DIGEST_SCHEMA,
        maxTokens: 1600,
        spend,
        model: MODEL,
      }),
      `${bookId(bookAt(c.order))} ${c.label}`,
    );
    if (d?.resume) store("chapters", key(c), d);
  }, progress("chapitres"));

  console.log(`\n  ${spend.calls} appels · ${dollars(spend).toFixed(2)} $ cumulés`);
}

/**
 * Clé de cache d'un chapitre.
 *
 * Elle porte l'épopée : sans elle, le chapitre 5 du tome 1 des Chevaliers et
 * celui des Héritiers partageraient la même entrée, et la seconde épopée
 * hériterait silencieusement des résumés de la première.
 */
const key = (c: { order: number; chapter: number }) =>
  `${bookId(bookAt(c.order))}-C${String(c.chapter).padStart(3, "0")}`;

// ── Passe 2 : fiches d'entité ─────────────────────────────────────────────

type Aggregate = {
  canonical: string;
  variants: Map<string, number>;
  kind: EntityKind;
  books: Set<number>;
  notes: { order: number; label: string; role: string }[];
  firstSeen: string;
};

/**
 * Regroupe les mentions par entité.
 *
 * Le modèle écrit tantôt « Kira », tantôt « Kira d'Émeraude » : on replie le
 * complément de nom quand la forme courte existe déjà par ailleurs, et on garde
 * la forme longue comme alias.
 */
function aggregate(chapters: ChapterText[]): Map<string, Aggregate> {
  const byKey = new Map<string, Aggregate>();

  for (const c of chapters) {
    const d = cached<Digest>("chapters", key(c));
    if (!d) continue;
    for (const m of d.entites ?? []) {
      const name = m.nom?.trim();
      if (!name || name.length < 2) continue;
      const k = fold(name);
      if (!k) continue;
      let agg = byKey.get(k);
      if (!agg) {
        agg = {
          canonical: name, variants: new Map(), kind: m.type, books: new Set(),
          notes: [], firstSeen: `${bookLabel(bookAt(c.order))}, ${c.label}`,
        };
        byKey.set(k, agg);
      }
      agg.variants.set(name, (agg.variants.get(name) ?? 0) + 1);
      agg.books.add(c.order);
      agg.notes.push({ order: c.order, label: c.label, role: m.role });
    }
  }

  // Replie « X de Y » sur « X » lorsque la forme courte est elle-même attestée.
  for (const [k, agg] of [...byKey]) {
    const head = k.replace(/ (de|du|des|d|la|le) .*$/, "");
    if (head === k || head.length < 3) continue;
    const target = byKey.get(head);
    if (!target || target.kind !== agg.kind) continue;
    for (const [v, n] of agg.variants) target.variants.set(v, (target.variants.get(v) ?? 0) + n);
    for (const t of agg.books) target.books.add(t);
    target.notes.push(...agg.notes);
    byKey.delete(k);
  }

  for (const agg of byKey.values()) {
    agg.canonical = [...agg.variants].sort((a, b) => b[1] - a[1])[0][0];
    agg.notes.sort((a, b) => a.order - b.order);
  }
  return byKey;
}

/**
 * Fusionne les noms qui désignent une même entité.
 *
 * Le dépouillement chapitre par chapitre nomme les personnages comme le fait le
 * texte : « Amecareth » ici, « l'Empereur Noir » là ; « Abnar » et « le Magicien
 * de Cristal » sont le même Immortel. Sans cette passe, chacun reçoit sa propre
 * fiche, bâtie sur la moitié de ses mentions — et la recherche par nom en rate
 * systématiquement une moitié.
 *
 * Aucune similarité de chaîne ne peut rapprocher « Amecareth » de « Empereur
 * Noir » : seul un lecteur du corpus le peut. On confie donc l'appariement au
 * modèle, en lui donnant un extrait des mentions de chaque nom pour trancher.
 */

const MERGE_SCHEMA = {
  type: "object",
  properties: {
    groupes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          canonique: { type: "string", description: "Le nom à retenir, obligatoirement l'un des membres." },
          membres: { type: "array", items: { type: "string" } },
        },
        required: ["canonique", "membres"],
        additionalProperties: false,
      },
    },
  },
  required: ["groupes"],
  additionalProperties: false,
};

const MERGE_SYSTEM = `Tu consolides l'index d'une encyclopédie sur « Les Chevaliers d'Émeraude » d'Anne Robillard.

On te donne des noms relevés dans les livres, chacun accompagné d'un extrait de ce qu'on en dit. Regroupe ceux qui désignent EXACTEMENT la même entité.

À regrouper :
- un nom propre et sa périphrase : « Amecareth » et « l'Empereur Noir » ; « Abnar » et « le Magicien de Cristal »
- un nom nu et sa forme titrée : « Fan », « Reine Fan de Shola », « la Reine de Shola »
- un singulier et son pluriel désignant le même ensemble : « Dragon » et « Dragons »

À NE PAS regrouper :
- deux personnes distinctes, même parentes ou homonymes — une mère et sa fille restent deux entités
- une personne et le lieu dont elle règne : « Shola » le royaume n'est pas « la Reine de Shola »
- un individu et le peuple auquel il appartient

Dans le doute, ne regroupe pas : une fusion abusive fond deux personnages en un seul et fausse toute l'encyclopédie.
N'émets QUE les groupes d'au moins deux membres — un groupe à un seul nom n'a aucun effet et gaspille la réponse. Si aucun regroupement ne s'impose, renvoie une liste vide.
« canonique » doit être le nom le plus reconnaissable parmi les membres.`;

type MergeGroup = { canonique: string; membres: string[] };

/** Réunit `from` dans `into`, en conservant les noms absorbés comme variantes. */
function absorb(into: Aggregate, from: Aggregate) {
  for (const [v, n] of from.variants) into.variants.set(v, (into.variants.get(v) ?? 0) + n);
  for (const t of from.books) into.books.add(t);
  into.notes.push(...from.notes);
  into.notes.sort((a, b) => a.order - b.order);
}

async function mergeIdentities(
  client: Anthropic,
  byKey: Map<string, Aggregate>,
  spend: Spend,
): Promise<void> {
  // Pluriels réguliers : déterministe, inutile de payer un appel pour cela.
  for (const [k, agg] of [...byKey]) {
    if (!k.endsWith("s") || k.length < 5) continue;
    const singular = byKey.get(k.slice(0, -1));
    if (!singular || singular.kind !== agg.kind) continue;
    absorb(singular, agg);
    byKey.delete(k);
  }

  const candidates = [...byKey.entries()]
    .filter(([, a]) => a.notes.length >= MIN_CHAPTERS)
    .sort((a, b) => b[1].notes.length - a[1].notes.length);

  const fingerprint = createHash("sha1")
    .update(candidates.map(([k]) => k).join("|"))
    .digest("hex")
    .slice(0, 12);

  let groups = cached<{ groupes: MergeGroup[] }>("merges", fingerprint)?.groupes;

  if (!groups) {
    console.log(`\nPasse 1bis — fusion des identités : ${candidates.length} noms à consolider`);
    const listing = candidates
      .map(([, a]) => `- ${a.canonical} (${a.kind}, ${a.notes.length} chapitres) : ${a.notes[0].role.slice(0, 120)}`)
      .join("\n");

    const r = await withRetry(
      () => askJson<{ groupes: MergeGroup[] }>(client, {
        system: MERGE_SYSTEM,
        prompt: `NOMS RELEVÉS :\n${listing}`,
        schema: MERGE_SCHEMA,
        // Le budget doit suivre le nombre de noms : à 538 candidats, 8 000
        // tokens tronquaient la réponse au milieu du JSON.
        maxTokens: Math.min(32000, 4000 + candidates.length * 40),
        spend,
        model: MODEL,
      }),
      "fusion des identités",
    );
    groups = r?.groupes ?? [];

    // Ne jamais mettre en cache un résultat vide : il vaut désactivation
    // définitive de la passe, alors qu'il traduit presque toujours un échec.
    const useful = groups.filter((g) => new Set(g.membres.map(fold)).size >= 2).length;
    if (useful) {
      store("merges", fingerprint, { groupes: groups });
    } else {
      console.warn(
        `  ⚠ fusion sans effet sur ${candidates.length} noms — non mise en cache, ` +
        `relancez pour réessayer`,
      );
    }
  }

  const byName = new Map<string, string>();
  for (const [k, a] of byKey) byName.set(fold(a.canonical), k);

  // Le modèle renvoie aussi des groupes à un seul nom, sans effet : les compter
  // comme des fusions donnerait « 21 noms fondus dans 314 groupes », un chiffre
  // qui laisse croire à un emballement alors que 18 groupes seulement agissent.
  const actionable = groups.filter((g) => new Set(g.membres.map(fold)).size >= 2).length;
  let merged = 0;
  for (const g of groups) {
    const keys = [...new Set(g.membres.map((m) => byName.get(fold(m))).filter(Boolean) as string[])];
    if (keys.length < 2) continue;

    const targetKey = byName.get(fold(g.canonique)) ?? keys[0];
    const target = byKey.get(targetKey);
    if (!target) continue;

    for (const k of keys) {
      if (k === targetKey) continue;
      const other = byKey.get(k);
      // Ne jamais fondre deux natures différentes : c'est le garde-fou contre
      // la confusion entre un souverain et son royaume.
      if (!other || other.kind !== target.kind) continue;
      absorb(target, other);
      byKey.delete(k);
      merged++;
    }
    target.canonical = g.canonique;
  }
  if (merged) console.log(`  ${merged} noms fondus · ${actionable} groupes exploitables sur ${groups.length} proposés`);
}

const CARD_SCHEMA = {
  type: "object",
  properties: {
    nom: { type: "string" },
    alias: { type: "array", items: { type: "string" } },
    type: { type: "string", enum: KINDS },
    accroche: { type: "string", description: "Une seule phrase, qui situe immédiatement." },
    description: { type: "string", description: "Un à trois paragraphes." },
    evolution: { type: "string", description: "Ce qui change pour cette entité au fil des tomes." },
    relations: {
      type: "array",
      items: {
        type: "object",
        properties: { nom: { type: "string" }, nature: { type: "string" } },
        required: ["nom", "nature"],
        additionalProperties: false,
      },
    },
  },
  required: ["nom", "alias", "type", "accroche", "description", "evolution", "relations"],
  additionalProperties: false,
};

const CARD_SYSTEM = `Tu rédiges une fiche d'encyclopédie sur « Les Chevaliers d'Émeraude » d'Anne Robillard.

On te donne toutes les mentions d'une même entité, relevées chapitre par chapitre et dans l'ordre des tomes. Fonds-les en une fiche cohérente.

Consignes :
- N'utilise que ce qui figure dans les mentions. N'ajoute aucun fait extérieur.
- Quand deux mentions se contredisent, retiens la plus étayée et signale la divergence.
- L'« évolution » doit être un vrai arc : ce que l'entité devient, pas une répétition de la description.
- Écris de façon dense et concrète. Pas de formules d'encyclopédie creuses.`;

/** Pièces qu'un incident réseau ou un solde épuisé a empêché de produire. */
const failures: string[] = [];

/** Liens de parenté qu'aucune fiche ne doit affirmer. */
let rejections: Rejection[] = [];

async function pass2(client: Anthropic, chapters: ChapterText[], spend: Spend): Promise<CodexEntry[]> {
  const byKey = aggregate(chapters);
  await mergeIdentities(client, byKey, spend);

  const aggs = [...byKey.entries()]
    .filter(([, a]) => a.notes.length >= MIN_CHAPTERS)
    .sort((a, b) => b[1].notes.length - a[1].notes.length);

  const todo = aggs.filter(([k, agg]) => !cached("entities", cardKey(k, agg)));
  console.log(`\nPasse 2 — fiches : ${aggs.length} entités retenues (seuil ${MIN_CHAPTERS} chapitres), ${todo.length} à rédiger`);

  await pool(todo, CONCURRENCY, async ([k, agg]) => {
    // Échantillonne largement mais uniformément si l'entité est omniprésente.
    const notes = agg.notes.length <= 60
      ? agg.notes
      : agg.notes.filter((_, i) => i % Math.ceil(agg.notes.length / 60) === 0);

    const body = notes
      .map((n) => `- ${bookLabel(bookAt(n.order))}, ${n.label} : ${n.role}`)
      .join("\n");

    const banned = rejectionsFor(agg.canonical, rejections);
    const warning = banned.length
      ? "\n\nLIENS À NE PAS AFFIRMER — une vérification les a écartés. N'énonce aucune " +
        "parenté entre ces personnes, ni dans la description, ni dans les liens :\n" +
        banned.map((r) => `- ${r.from} et ${r.to} : ${r.motif.slice(0, 160)}`).join("\n")
      : "";
    const card = await withRetry(
      () => askJson<{
        nom: string; alias: string[]; type: EntityKind; accroche: string;
        description: string; evolution: string; relations: { nom: string; nature: string }[];
      }>(client, {
        system: CARD_SYSTEM,
        prompt: `ENTITÉ : ${agg.canonical} (${agg.kind})\nVariantes relevées : ${[...agg.variants.keys()].join(", ")}\nTomes : ${[...agg.books].sort((a, b) => a - b).map((o) => bookLabel(bookAt(o))).join(" · ")}\n\nMENTIONS (${notes.length} sur ${agg.notes.length}) :\n${body}${warning}`,
        schema: CARD_SCHEMA,
        maxTokens: 2200,
        spend,
        model: MODEL,
      }),
      `fiche ${agg.canonical}`,
    );
    if (card?.accroche) {
      store("entities", cardKey(k, agg), {
        ...card,
        _agg: { bookIds: [...agg.books].map((o) => bookId(bookAt(o))), firstSeen: agg.firstSeen },
      });
    }
  }, progress("fiches  "));

  const entries: CodexEntry[] = [];
  for (const [k, agg] of aggs) {
    const c = cached<Record<string, never>>("entities", cardKey(k, agg));
    if (!c) { failures.push(`fiche ${agg.canonical}`); continue; }
    const raw = c as unknown as {
      nom: string; alias: string[]; type: EntityKind; accroche: string;
      description: string; evolution: string; relations: { nom: string; nature: string }[];
      _agg: { bookIds: string[]; firstSeen: string };
    };
    entries.push({
      id: slug(k),
      kind: KINDS.includes(raw.type) ? raw.type : agg.kind,
      name: raw.nom || agg.canonical,
      aliases: [...new Set([...(raw.alias ?? []), ...agg.variants.keys()])].filter((a) => fold(a) !== fold(raw.nom)),
      gloss: raw.accroche,
      description: raw.description,
      arc: raw.evolution,
      relations: (raw.relations ?? []).map((r) => ({ name: r.nom, nature: r.nature })),
      books: raw._agg.bookIds
        .map((id) => BOOKS.find((b) => bookId(b) === id)?.order)
        .filter((o): o is number => o !== undefined)
        .sort((a, b) => a - b),
      firstSeen: raw._agg.firstSeen,
    });
  }
  console.log(`\n  ${entries.length} fiches · ${dollars(spend).toFixed(2)} $ cumulés`);
  return entries;
}

const slug = (k: string) => k.replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60) || "x";

/**
 * Clé de cache d'une fiche, empreinte des mentions comprise.
 *
 * Une fiche résume TOUTES les mentions d'une entité. Si le cache ne dépendait
 * que du nom, une exécution partielle (`--tomes 1,2`) figerait une fiche bâtie
 * sur deux tomes, que l'exécution complète réutiliserait telle quelle — une
 * fiche silencieusement amputée de dix tomes. L'empreinte force sa réécriture
 * dès que l'ensemble des mentions change.
 */
function cardKey(k: string, agg: Aggregate): string {
  // Les exclusions entrent dans l'empreinte : corriger une parenté doit
  // refaire la fiche concernée, et elle seule.
  const banned = rejectionsFor(agg.canonical, rejections)
    .map((r) => `${r.from}>${r.to}`)
    .sort()
    .join(",");
  // L'empreinte cite les tomes par leur identifiant stable, jamais par leur
  // position : insérer un hors-série au milieu de la série décale toutes les
  // positions suivantes et invaliderait, sans raison, des fiches inchangées.
  const material = agg.notes
    .map((n) => `${bookId(bookAt(n.order))}|${n.label}|${n.role}`)
    .join("\n") + (banned ? `\n!${banned}` : "");
  // Le marqueur n'est ajouté que s'il y a réellement une exclusion : l'ajouter
  // à vide changerait l'empreinte de chaque fiche et referait tout le Codex.
  const digest = createHash("sha1").update(material).digest("hex").slice(0, 10);
  return `${slug(k)}.${digest}`;
}

// ── Passe 3 : synopsis par tome ───────────────────────────────────────────

const SYNOPSIS_SCHEMA = {
  type: "object",
  properties: { synopsis: { type: "string" } },
  required: ["synopsis"],
  additionalProperties: false,
};

async function pass3(client: Anthropic, chapters: ChapterText[], spend: Spend) {
  const orders = [...new Set(chapters.map((c) => c.order))].sort((a, b) => a - b);
  const todo = orders.filter((o) => !cached("synopses", bookId(bookAt(o))));
  console.log(`\nPasse 3 — synopsis : ${orders.length} tomes, ${todo.length} à rédiger`);

  await pool(todo, 4, async (t) => {
    const body = chapters
      .filter((c) => c.order === t)
      .map((c) => {
        const d = cached<Digest>("chapters", key(c));
        return d ? `${c.label}\n${d.resume}` : null;
      })
      .filter(Boolean)
      .join("\n\n");
    if (!body) return;

    const r = await withRetry(
      () => askJson<{ synopsis: string }>(client, {
        system: `Tu rédiges le synopsis d'un tome des « Chevaliers d'Émeraude » à partir des résumés de ses chapitres.
Six à dix phrases : l'intrigue principale, les bascules, l'état des lieux à la fin du tome. Ne t'interdis aucune révélation — ce texte sert de référence interne, pas de quatrième de couverture.`,
        prompt: `${bookLabel(bookAt(t))}\n\n${body}`,
        schema: SYNOPSIS_SCHEMA,
        maxTokens: 1400,
        spend,
        model: MODEL,
      }),
      `synopsis T${t}`,
    );
    if (r?.synopsis) store("synopses", bookId(bookAt(t)), r);
  }, progress("synopsis"));
}

// ── Assemblage ────────────────────────────────────────────────────────────

async function main() {
  rejections = loadRejections(ROOT);
  if (rejections.length) console.log(`${rejections.length} liens de parenté écartés par vérification`);

  console.log("Lecture des tomes…");
  const chapters = readChapters();
  const chars = chapters.reduce((s, c) => s + c.text.length, 0);
  console.log(`${chapters.length} chapitres · ${(chars / 1e6).toFixed(1)} M caractères`);

  if (DRY) {
    // Le cache décide du coût réel : seuls les chapitres absents seront payés.
    const todo = chapters.filter((c) => !cached("chapters", key(c)));
    const todoChars = todo.reduce((n, c) => n + c.text.length, 0);
    // ~3,6 caractères par token en français.
    const estimate = (n: number, cs: number) => {
      const inTok = cs / 3.6 + n * 250;
      const outTok = n * 420;
      return { inTok, outTok, cost: (inTok / 1e6) * 1 + (outTok / 1e6) * 5 };
    };
    const full = estimate(chapters.length, chars);
    const rest = estimate(todo.length, todoChars);

    console.log(`\nPasse 1 (${MODEL}) :`);
    console.log(`  ${chapters.length - todo.length} chapitres déjà en cache, ${todo.length} à calculer`);
    console.log(`  entrée  ~${(rest.inTok / 1e6).toFixed(2)} M tokens`);
    console.log(`  sortie  ~${(rest.outTok / 1e6).toFixed(2)} M tokens`);
    console.log(`  coût    ~${rest.cost.toFixed(2)} $   (${full.cost.toFixed(2)} $ sans le cache)`);
    console.log(`\nÀ dépenser : ~${(rest.cost + full.cost * 0.25).toFixed(2)} $`);
    console.log(`  Les passes 2 et 3 sont recalculées intégralement dès que les mentions`);
    console.log(`  changent : une fiche résume TOUTES les mentions de son entité.`);
    console.log(`\nRelancez sans --dry-run pour construire.`);
    return;
  }

  const cred = credentials();
  if (!cred.source) {
    console.error("Aucun identifiant Anthropic : renseignez ANTHROPIC_API_KEY dans .env.local,");
    console.error("ou connectez un profil avec `ant auth login`.");
    process.exit(1);
  }
  if (cred.warning) console.warn(`⚠ ${cred.warning}`);
  console.log(`Authentification : ${cred.label}\n`);

  const client = new Anthropic();
  const spend = newSpend();

  await pass1(client, chapters, spend);
  const entries = await pass2(client, chapters, spend);
  await pass3(client, chapters, spend);

  const summaries: ChapterSummary[] = [];
  for (const c of chapters) {
    const d = cached<Digest>("chapters", key(c));
    if (d?.resume) summaries.push({ book: c.order, chapter: c.chapter, label: c.label, pageStart: c.page, summary: d.resume });
  }

  const synopses = [...new Set(chapters.map((c) => c.order))]
    .sort((a, b) => a - b)
    .map((o) => {
      const syn = cached<{ synopsis: string }>("synopses", bookId(bookAt(o)))?.synopsis ?? "";
      if (!syn) failures.push(`synopsis ${bookId(bookAt(o))}`);
      return { book: o, synopsis: syn };
    })
    .filter((s) => s.synopsis);

  const codex: Codex = {
    builtAt: new Date().toISOString(),
    model: MODEL,
    entries,
    chapters: summaries,
    synopses,
  };

  fs.mkdirSync(OUT, { recursive: true });
  const outPath = path.join(OUT, "codex.json");

  /*
   * Un Codex incomplet ne doit jamais en remplacer un complet.
   *
   * Le solde de crédits s'est épuisé au milieu d'une exécution : quarante-cinq
   * fiches et deux synopsis n'ont pu être écrits, et le fichier assemblé — plus
   * pauvre que celui qu'il écrasait — a été enregistré quand même. Une panne
   * passagère avait dégradé un résultat acquis.
   *
   * Les résumés déjà calculés restent en cache : reprendre après recharge ne
   * repaie que ce qui manque.
   */
  if (failures.length) {
    const previous = fs.existsSync(outPath)
      ? (JSON.parse(fs.readFileSync(outPath, "utf8")) as Codex)
      : null;
    const worse = previous && previous.entries.length > codex.entries.length;

    console.error(`\n${failures.length} pièces manquantes :`);
    for (const f of failures.slice(0, 8)) console.error(`  ${f}`);
    if (failures.length > 8) console.error(`  … et ${failures.length - 8} autres`);

    if (worse) {
      console.error(
        `\ncodex.json CONSERVÉ EN L'ÉTAT (${previous!.entries.length} fiches) : ` +
        `l'assemblage n'en compte que ${codex.entries.length}.`,
      );
      console.error("Relancez `npm run codex` — le cache ne fera repayer que les pièces manquantes.");
      process.exit(1);
    }
    console.error("\nCodex écrit malgré ces manques (il ne dégrade pas le précédent).");
  }

  fs.writeFileSync(outPath, JSON.stringify(codex));

  const byKind: Record<string, number> = {};
  for (const e of entries) byKind[e.kind] = (byKind[e.kind] ?? 0) + 1;

  console.log(`\n\nCodex construit`);
  console.log(`  ${entries.length} fiches — ${Object.entries(byKind).map(([k, n]) => `${n} ${k}`).join(", ")}`);
  console.log(`  ${summaries.length} résumés de chapitre · ${synopses.length} synopsis`);
  console.log(`  ${spend.calls} appels · ${(spend.input / 1e6).toFixed(2)} M tokens en entrée · ${dollars(spend).toFixed(2)} $`);
  console.log(`  → data/index/codex.json (${(fs.statSync(path.join(OUT, "codex.json")).size / 1e6).toFixed(1)} Mo)`);
  console.log(`\nRedémarrez le serveur pour que l'Oracle le charge.`);
}

main();
