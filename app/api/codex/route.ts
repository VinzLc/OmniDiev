import { loadCodex } from "@/lib/codex.ts";
import { BOOKS, bookAt, sagaOf, SAGAS, ROMAN } from "@/lib/books.ts";

export const runtime = "nodejs";

/**
 * Index allégé du Codex, pour la grille.
 *
 * La liste complète pèse 0,9 Mo, l'index 107 Ko : on envoie l'index une fois —
 * la recherche et les filtres deviennent instantanés, sans aller-retour — et le
 * détail d'une fiche à la demande.
 */
export async function GET() {
  const l = loadCodex();
  if (!l) {
    return Response.json({ ready: false, entries: [], sagas: [], books: [] });
  }

  // Numérotation stable, dans l'ordre d'entrée en scène : les figures des
  // premiers tomes ouvrent le recueil, celles d'Antarès le referment.
  const ordered = [...l.codex.entries].sort((a, b) => {
    const fa = a.books[0] ?? 999;
    const fb = b.books[0] ?? 999;
    return fa - fb || a.name.localeCompare(b.name, "fr");
  });

  return Response.json({
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
    entries: ordered.map((e, i) => ({
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
  });
}
