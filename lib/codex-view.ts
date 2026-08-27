/**
 * Mise en forme des données du Codex pour l'affichage.
 *
 * Une seule implémentation, deux consommateurs : les routes d'API de
 * l'application locale et le générateur du site statique. Les dupliquer aurait
 * garanti qu'elles finissent par diverger — le site publié montrant autre chose
 * que l'application.
 */
import fs from "node:fs";
import path from "node:path";
import { loadCodex, type CodexEntry } from "./codex.ts";
import { BOOKS, SAGAS, ROMAN, bookAt, bookLabel, sagaOf } from "./books.ts";
import { fold } from "./text.ts";

export type IndexEntry = {
  n: number;
  /** Le visage dessiné pour le jeu, s'il existe. */
  portrait: string | null;
  id: string;
  name: string;
  kind: string;
  gloss: string;
  books: number[];
  sagas: number[];
  aliases: number;
  relations: number;
  first: number;
  firstSaga: string;
};

export type CodexIndex = {
  ready: boolean;
  builtAt?: string;
  sagas: { id: number; name: string; short: string; from: number; to: number }[];
  books: { order: number; saga: number; label: string; title: string }[];
  entries: IndexEntry[];
};

/**
 * Les fiches qui ont un visage.
 *
 * Les portraits sont dessinés pour le jeu, mais rien ne justifie que le Codex
 * s'en prive : une fiche illustrée se retient, une fiche de texte se parcourt.
 * On relève les fichiers présents une fois, plutôt que d'interroger le disque
 * pour chacune des cinq cent onze fiches.
 */
let visages: Set<string> | null = null;
function aUnPortrait(id: string): boolean {
  if (!visages) {
    const dir = path.join(process.cwd(), "jeu", "art", "portraits");
    // Un identifiant de fiche peut contenir un tiret — « emeraude-ier ». On ne
    // peut donc pas s'en servir pour reconnaître les humeurs : on relève tout,
    // et c'est la correspondance avec un identifiant connu qui tranche.
    visages = new Set(
      fs.existsSync(dir)
        ? fs.readdirSync(dir)
            .filter((f) => f.endsWith(".png") && !f.startsWith("."))
            .map((f) => f.slice(0, -4))
        : [],
    );
  }
  return visages.has(id);
}


/** Ordre de parution des entités : les figures des premiers tomes ouvrent. */
/**
 * L'ordre des fiches, et donc leur numéro.
 *
 * Exporté parce que le jeu numérote les siennes de la même façon : « N° 062 »
 * doit désigner Wellan sur le site comme dans le Codex du jeu. Deux tris
 * séparés auraient fini par diverger, et personne ne l'aurait vu.
 */
export function ordered(entries: CodexEntry[]): CodexEntry[] {
  return [...entries].sort((a, b) => {
    const fa = a.books[0] ?? 999;
    const fb = b.books[0] ?? 999;
    return fa - fb || a.name.localeCompare(b.name, "fr");
  });
}

export function codexIndex(): CodexIndex {
  const l = loadCodex();
  if (!l) return { ready: false, sagas: [], books: [], entries: [] };

  return {
    ready: true,
    builtAt: l.codex.builtAt,
    sagas: SAGAS.map((s) => ({
      id: s.id,
      name: s.name,
      short: s.short,
      from: BOOKS.find((b) => b.saga === s.id)!.order,
      to: [...BOOKS].reverse().find((b) => b.saga === s.id)!.order,
    })),
    books: BOOKS.map((b) => ({
      order: b.order,
      saga: b.saga,
      label: b.tome === 0 ? "Hors-série" : `Tome ${ROMAN[b.tome]}`,
      title: b.title,
    })),
    entries: ordered(l.codex.entries).map((e, i) => ({
      n: i + 1,
      portrait: aUnPortrait(e.id) ? `portraits/${e.id}.png` : null,
      id: e.id,
      name: e.name,
      kind: e.kind,
      gloss: e.gloss,
      books: e.books,
      sagas: [...new Set(e.books.map((o) => bookAt(o).saga))].sort(),
      aliases: e.aliases.length,
      relations: e.relations.length,
      first: e.books[0] ?? 999,
      firstSaga: e.books.length ? sagaOf(bookAt(e.books[0]).saga).short : "",
    })),
  };
}

/** Fiche complète, renvois vers d'autres fiches résolus. */
export function codexDetail(id: string) {
  const l = loadCodex();
  const entry = l?.codex.entries.find((e) => e.id === id);
  if (!entry) return null;

  // Un lien ne vaut que s'il mène quelque part : seules les relations
  // correspondant à une fiche existante deviennent cliquables.
  const byName = new Map(l!.codex.entries.map((e) => [fold(e.name), e.id]));
  for (const e of l!.codex.entries) {
    for (const a of e.aliases) if (!byName.has(fold(a))) byName.set(fold(a), e.id);
  }

  return {
    ...entry,
    portrait: aUnPortrait(entry.id) ? `portraits/${entry.id}.png` : null,
    volumes: entry.books.map((o) => {
      const b = bookAt(o);
      return {
        order: o,
        saga: b.saga,
        sagaShort: sagaOf(b.saga).short,
        label: b.tome === 0 ? "Hors-série" : ROMAN[b.tome],
        full: bookLabel(b),
      };
    }),
    relations: entry.relations.map((r) => ({
      ...r,
      target: byName.get(fold(r.name)) ?? null,
    })),
  };
}

/** Identifiants de toutes les fiches, pour la génération statique. */
export function codexIds(): string[] {
  return loadCodex()?.codex.entries.map((e) => e.id) ?? [];
}
