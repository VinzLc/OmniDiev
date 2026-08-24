/**
 * Mise en forme des données du Codex pour l'affichage.
 *
 * Une seule implémentation, deux consommateurs : les routes d'API de
 * l'application locale et le générateur du site statique. Les dupliquer aurait
 * garanti qu'elles finissent par diverger — le site publié montrant autre chose
 * que l'application.
 */
import { loadCodex, type CodexEntry } from "./codex.ts";
import { BOOKS, SAGAS, ROMAN, bookAt, bookLabel, sagaOf } from "./books.ts";
import { fold } from "./text.ts";

export type IndexEntry = {
  n: number;
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

/** Ordre de parution des entités : les figures des premiers tomes ouvrent. */
function ordered(entries: CodexEntry[]): CodexEntry[] {
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
