import type { ParsedBook } from "./parse.ts";
import { bookId, bookLabel, type Book } from "./books.ts";

export type Chunk = {
  id: string;
  /** Épopée (1 ou 2). */
  saga: number;
  /** Numéro du tome dans son épopée. */
  tome: number;
  /** Position absolue dans la chronologie, 1 à 24 : base du filtrage. */
  order: number;
  bookTitle: string;
  /** Index du chapitre dans le tome ; -1 hors chapitre. */
  chapter: number;
  chapterLabel: string;
  pageStart: number;
  pageEnd: number;
  /** Référence lisible, reprise telle quelle dans les citations. */
  ref: string;
  text: string;
};

/**
 * Regroupe les paragraphes en fragments d'environ `target` caractères.
 *
 * Les fragments ne franchissent jamais une frontière de chapitre : un fragment
 * à cheval sur deux chapitres produirait une citation dont la référence serait
 * fausse pour la moitié du texte. Le dernier paragraphe est reporté dans le
 * fragment suivant, afin qu'une scène coupée en deux reste retrouvable par
 * l'une ou l'autre moitié.
 */
export function chunkBook(parsed: ParsedBook, target = 1400, max = 2100): Chunk[] {
  const book: Book = parsed.book;
  const prefix = bookId(book);
  const label = bookLabel(book);
  const chunks: Chunk[] = [];
  let n = 0;

  const emit = (paras: { text: string; page: number }[], chapter: number) => {
    if (!paras.length) return;
    const text = paras.map((p) => p.text).join("\n\n");
    if (text.trim().length < 120) return; // trop court pour porter du sens
    const chapterLabel = parsed.chapters[chapter]?.label ?? "Hors chapitre";
    const pageStart = paras[0].page;
    const pageEnd = paras[paras.length - 1].page;
    const pages = pageStart === pageEnd ? `p. ${pageStart}` : `p. ${pageStart}-${pageEnd}`;
    chunks.push({
      id: `${prefix}-${String(++n).padStart(4, "0")}`,
      saga: book.saga,
      tome: book.tome,
      order: book.order,
      bookTitle: book.title,
      chapter,
      chapterLabel,
      pageStart,
      pageEnd,
      ref: `${label}, ${chapterLabel}, ${pages}`,
      text,
    });
  };

  let buf: { text: string; page: number }[] = [];
  let len = 0;
  let curChapter = parsed.paragraphs[0]?.chapter ?? -1;

  for (const para of parsed.paragraphs) {
    if (para.chapter !== curChapter) {
      emit(buf, curChapter);
      buf = [];
      len = 0;
      curChapter = para.chapter;
    }

    // Un paragraphe plus long que `max` forme un fragment à lui seul.
    if (para.text.length > max) {
      emit(buf, curChapter);
      emit([para], curChapter);
      buf = [];
      len = 0;
      continue;
    }

    if (len + para.text.length > target && buf.length) {
      emit(buf, curChapter);
      const carry = buf[buf.length - 1];
      buf = carry.text.length < 600 ? [carry] : [];
      len = buf.reduce((s, p) => s + p.text.length, 0);
    }

    buf.push(para);
    len += para.text.length;
  }
  emit(buf, curChapter);

  return chunks;
}
