/**
 * Reconstruit un livre lisible à partir de la sortie `pdftotext -layout`.
 *
 * `-layout` conserve l'indentation, ce qui donne trois signaux exploitables :
 *   - un alinéa (indentation supérieure au corps de texte) ouvre un paragraphe ;
 *   - les en-têtes courants et les folios sont seuls sur leur ligne ;
 *   - la césure de fin de ligne est préservée telle quelle.
 */

import { bookId, type Book } from "./books.ts";

export type Chapter = {
  /** Numéro imprimé, `null` pour un prologue ou un épilogue. */
  number: number | null;
  title: string;
  /** Intitulé brut relevé dans le texte, avant contrôle de lisibilité. */
  rawTitle: string;
  /** Libellé affichable, ex. « Chapitre 6 — Le peuple des forêts ». */
  label: string;
};

export type Paragraph = {
  text: string;
  /** Page imprimée où débute le paragraphe. */
  page: number;
  /** Index dans `ParsedBook.chapters`, ou -1 pour le hors-chapitre. */
  chapter: number;
};

export type ParsedBook = {
  book: Book;
  chapters: Chapter[];
  paragraphs: Paragraph[];
  warnings: string[];
};

type Line = { raw: string; text: string; indent: number; page: number };

const deaccent = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
const lettersOnly = (s: string) => deaccent(s).toLowerCase().replace(/[^a-z]/g, "");

/** Folio isolé sur sa ligne : « 62 », « - 62 - », « — 62 — ». */
const FOLIO = /^\s*[-–—]?\s*(\d{1,4})\s*[-–—]?\s*$/;

/**
 * Titre de chapitre sur deux lignes : le numéro seul, puis le titre.
 * Le numéro est parfois précédé du mot « Chapitre », comme dans le hors-série
 * « Les premiers Chevaliers ».
 */
const CHAP_NUM_ALONE = /^\s{4,}(?:Chapitres?\s+)?(\d{1,3})\s*[.．]?\s*$/i;

/** Titre de chapitre sur une ligne : « 1. Le contrechoc ». */
const CHAP_INLINE = /^\s{4,}(\d{1,3})\s*[.．]\s+(\S.{0,60})$/;

const FRONT_HEADING = /^\s*(prologue|avant[-\s]?propos)\s*$/i;
const BACK_HEADING = /^\s*(épilogue|epilogue)\s*$/i;

/**
 * Repère les en-têtes courants par leur répétition, sans rien savoir du livre.
 *
 * Coder le titre en dur ne tient pas : chaque épopée a le sien, l'en-tête
 * alterne souvent entre le nom de la saga au verso et le titre du tome au
 * recto, et l'OCR le déforme d'une page à l'autre — « Les Héritiers d'Enkidiev »
 * se lit tour à tour « lesderimersenkdev », « lesderitiersenkeev »,
 * « lesoueuxailes ». Ce qui reste vrai partout, c'est qu'un en-tête revient sur
 * une grande partie des pages, toujours en première ligne, court et sans
 * ponctuation de phrase.
 *
 * Les variantes déformées trop rares pour franchir le seuil sont rattrapées par
 * proximité de trigrammes avec les formes dominantes.
 */

function headerKey(text: string): string | null {
  const t = text.trim();
  if (!t || t.length > 70) return null;
  if (/[.!?…,;:»"]$/.test(t)) return null;
  const k = lettersOnly(t);
  return k.length >= 6 ? k : null;
}

function trigrams(s: string): Set<string> {
  const out = new Set<string>();
  for (let i = 0; i + 3 <= s.length; i++) out.add(s.slice(i, i + 3));
  return out;
}

function overlap(a: Set<string>, b: Set<string>): number {
  if (!a.size || !b.size) return 0;
  let hits = 0;
  for (const g of a) if (b.has(g)) hits++;
  return hits / Math.min(a.size, b.size);
}

type HeaderModel = { forms: Set<string>; grams: Set<string>[] };

function detectHeaders(physical: string[]): HeaderModel {
  const counts = new Map<string, number>();
  let pages = 0;

  for (const page of physical) {
    const first = page.split("\n").find((l) => l.trim());
    if (first === undefined) continue;
    pages++;
    const k = headerKey(first);
    if (k) counts.set(k, (counts.get(k) ?? 0) + 1);
  }

  // 6 % des pages : au-dessus, une ligne récurrente est un ornement de mise en
  // page, pas une phrase du roman.
  const threshold = Math.max(8, Math.round(pages * 0.06));
  const forms = new Set([...counts].filter(([, n]) => n >= threshold).map(([k]) => k));
  return { forms, grams: [...forms].map(trigrams) };
}

function isRunningHeader(text: string, indent: number, model: HeaderModel, atTop: boolean): boolean {
  const k = headerKey(text);
  if (!k) return false;
  if (atTop && model.forms.has(k)) return true;

  const g = trigrams(k);
  // Variante déformée : même ornement, lettres abîmées.
  if (atTop && indent >= 3 && model.grams.some((h) => overlap(g, h) >= 0.6)) return true;

  // L'en-tête n'est pas toujours reconnu comme première ligne : sur certaines
  // pages la mise en page le rejette plus bas, et il s'insère alors en plein
  // milieu d'un paragraphe. Ailleurs qu'en tête, on exige une quasi-identité
  // pour ne pas amputer une vraie ligne de texte.
  return indent >= 3 && model.grams.some((h) => overlap(g, h) >= 0.85);
}

/**
 * Découpe le fichier en lignes annotées, en suivant le folio imprimé.
 *
 * Dans les douze tomes, le folio est toujours la dernière ligne non vide de la
 * page — jamais ailleurs. C'est ce qui permet de ne pas le confondre avec un
 * numéro de chapitre isolé, qui a exactement la même forme.
 */
function toLines(rawText: string): { lines: Line[]; pages: number } {
  const physical = rawText.split("\f");
  const headers = detectHeaders(physical);
  const lines: Line[] = [];
  // Le folio imprimé diffère de la page physique (pages liminaires non
  // numérotées, folios perdus par l'OCR) : on le suit quand il est lisible,
  // on l'extrapole sinon.
  let printed = 0;

  for (const pageText of physical) {
    const rawLines = pageText.split("\n").map((l) => l.replace(/\s+$/, ""));
    let lastIdx = -1;
    for (let i = rawLines.length - 1; i >= 0; i--) {
      if (rawLines[i].trim()) { lastIdx = i; break; }
    }
    if (lastIdx < 0) continue;

    const m = rawLines[lastIdx].match(FOLIO);
    const n = m ? Number(m[1]) : NaN;
    // Un folio plausible poursuit la progression ; au-delà c'est un nombre
    // appartenant au texte, qu'il faut conserver.
    const isFolio = m !== null && n > 0 && n < 2000 && (printed === 0 || Math.abs(n - printed - 1) <= 2);
    printed = isFolio ? n : printed + 1;

    let firstSeen = false;
    for (let i = 0; i < rawLines.length; i++) {
      if (isFolio && i === lastIdx) continue;
      const raw = rawLines[i];
      const text = raw.trim();
      if (!text) {
        lines.push({ raw, text: "", indent: 0, page: printed });
        continue;
      }
      const indent = raw.length - raw.trimStart().length;
      const atTop = !firstSeen;
      firstSeen = true;
      if (isRunningHeader(text, indent, headers, atTop)) continue;
      lines.push({ raw, text, indent, page: printed });
    }
  }
  return { lines, pages: printed };
}

/**
 * Indentation du corps de texte, estimée par le mode des indentations.
 * Les lignes de continuation sont largement majoritaires, donc leur
 * indentation est le mode.
 */
function bodyIndent(lines: Line[]): number {
  const counts = new Map<number, number>();
  for (const l of lines) {
    if (!l.text) continue;
    counts.set(l.indent, (counts.get(l.indent) ?? 0) + 1);
  }
  let best = 0, bestN = -1;
  for (const [indent, n] of counts) if (n > bestN) { best = indent; bestN = n; }
  return best;
}

/** Recolle une ligne à la précédente en résolvant la césure. */
function joinLine(acc: string, next: string, vocab: Map<string, number> | null): string {
  if (!acc) return next;
  const m = acc.match(/([A-Za-zÀ-ÿ]{1,})[-‑¬\u00ad]$/);
  if (m) {
    const head = m[1];
    const tail = next.match(/^([A-Za-zÀ-ÿ]+)/)?.[1] ?? "";
    if (tail) {
      // « Peut-être » coupé après le trait d'union est un vrai trait d'union ;
      // « compa-gnons » est une césure typographique. Le vocabulaire du corpus
      // tranche : on garde la forme réellement attestée.
      const glued = (head + tail).toLowerCase();
      const hyphenated = (head + "-" + tail).toLowerCase();
      const gN = vocab?.get(glued) ?? 0;
      const hN = vocab?.get(hyphenated) ?? 0;
      if (gN >= hN) return acc.slice(0, -1) + next; // césure : on soude
      return acc + next;                             // vrai trait d'union
    }
  }
  return acc + " " + next;
}

/**
 * Recolle une lettrine détachée de son mot.
 *
 * Les capitales ornées d'ouverture de chapitre sont composées à part, et
 * l'extraction les rend séparées : « T out comme… », « L e nouveau roi… ».
 * On ne recolle que les lettres qui ne forment pas un mot français à elles
 * seules, faute de quoi « À travers » ou « Y avait-il » y passeraient aussi.
 */
const STANDALONE_LETTERS = new Set(["A", "À", "Y", "O", "Ô"]);

function mergeDropCap(text: string): string {
  const m = text.match(/^([A-ZÀ-Ý])\s+([a-zà-ÿ]\S*)/);
  if (!m || STANDALONE_LETTERS.has(m[1])) return text;
  return m[1] + text.slice(m[0].length - m[2].length);
}

/**
 * Nombre de paragraphes consécutifs de prose qui signalent le début du roman.
 *
 * Quand aucun titre ne borne les pages liminaires, il faut un autre repère. Les
 * distinguer à leur vocabulaire est un jeu perdu — après « Anne Robillard »
 * vient « Claudia Robillard », après « Illustration » vient « Catalogage » — et
 * à leur ponctuation aussi : « Sommaire : t. 2. Basilics » offre deux points de
 * phrase parfaitement trompeurs.
 *
 * Ce qui sépare vraiment les deux, c'est la continuité. Une page d'éditeur tient
 * en un ou deux blocs isolés entre des lignes courtes ; le roman, lui, ne
 * s'arrête plus. On attend donc une série ininterrompue.
 */
const PROSE_RUN = 3;
const PROSE_MIN = 120;

type Candidate = { line: number; number: number; title: string; page: number };

/** Un livre ne dépasse pas la centaine de chapitres ; un folio, si. */
const MAX_CHAPTER = 99;

/**
 * Retrait, au-delà du corps de texte, à partir duquel une ligne est centrée.
 * Les alinéas de paragraphe valent trois à quatre espaces ; les titres, seize
 * à quarante.
 */
const CENTERED = 8;

/**
 * Indices des lignes situées en tête de page.
 *
 * Contrainte décisive : dans les vingt-quatre tomes, un titre de chapitre ouvre
 * toujours une page. Sans elle, un folio ayant échappé au filtre — il en reste
 * dès que la numérotation décroche — se fait passer pour un numéro de chapitre,
 * et comme les folios croissent régulièrement, ils forment la plus longue suite
 * croissante possible : le tome 9 des Héritiers y gagnait 361 chapitres pour
 * 461 pages.
 */
function pageTops(body: Line[], depth = 3): Set<number> {
  const tops = new Set<number>();
  let page = -1;
  let seen = 0;
  for (let i = 0; i < body.length; i++) {
    if (body[i].page !== page) { page = body[i].page; seen = 0; }
    if (!body[i].text) continue;
    if (seen < depth) tops.add(i);
    seen++;
  }
  return tops;
}

/** Relève tous les titres de chapitre numérotés plausibles, sans arbitrer. */
function findHeadings(body: Line[], tops: Set<number>, base: number): Candidate[] {
  const out: Candidate[] = [];
  for (let i = 0; i < body.length; i++) {
    const line = body[i];
    if (!line.text || !tops.has(i)) continue;

    const inline = line.raw.match(CHAP_INLINE);
    if (inline && Number(inline[1]) <= MAX_CHAPTER) {
      out.push({ line: i, number: Number(inline[1]), title: inline[2], page: line.page });
      continue;
    }
    const alone = line.raw.match(CHAP_NUM_ALONE);
    if (alone && Number(alone[1]) <= MAX_CHAPTER) {
      // Le titre suit, sur l'une des trois lignes suivantes — s'il existe.
      //
      // Il doit être CENTRÉ, pas seulement indenté : l'alinéa qui ouvre un
      // paragraphe l'est tout autant. Plusieurs tomes d'Ashur-Sîn font suivre le
      // numéro directement par le récit, et le seuil laxiste transformait la
      // première phrase du chapitre en titre — « Chapitre 1 — Ce ne fut qu'à
      // l'issue d'un terrible assaut de la part des Chevaliers ».
      let title = "";
      let j = i;
      for (let k = i + 1; k < Math.min(i + 4, body.length); k++) {
        if (!body[k].text) continue;
        if (body[k].text.length <= 70 && body[k].indent >= base + CENTERED) {
          title = body[k].text;
          j = k;
        }
        break;
      }
      out.push({ line: j, number: Number(alone[1]), title, page: line.page });
    }
  }
  return out;
}

/**
 * Titres de chapitre non numérotés — un intitulé centré, en capitales.
 *
 * « Abussos » ne numérote pas ses chapitres : il les ouvre par « RÉVÉLATIONS »,
 * « MAXIMILIEN », « DOIGTS MAGIQUES ». Sans ce second motif, le tome entier
 * était rejeté faute de repère.
 */
function findUnnumberedHeadings(body: Line[], tops: Set<number>): Candidate[] {
  const out: Candidate[] = [];
  let n = 0;
  for (let i = 0; i < body.length; i++) {
    const line = body[i];
    if (!line.text || !tops.has(i)) continue;
    if (line.indent < 6 || line.text.length > 50 || line.text.length < 3) continue;
    if (/[.!?…,;:»"]$/.test(line.text)) continue;
    if (/^[—–-]/.test(line.text)) continue; // réplique, pas un titre

    const letters = line.text.replace(/[^A-Za-zÀ-ÿŒœ]/g, "");
    if (letters.length < 3) continue;
    const upper = letters.replace(/[^A-ZÀ-ÝŒ]/g, "").length;
    if (upper / letters.length < 0.7) continue;

    // Un titre est suivi d'une ligne vide, jamais d'une suite de texte.
    if (body[i + 1]?.text) continue;

    out.push({ line: i, number: ++n, title: line.text, page: line.page });
  }
  return out;
}

/**
 * Retient la plus longue suite de candidats dont les numéros croissent.
 *
 * Un simple compteur séquentiel cale dès qu'un titre est illisible : c'est le
 * cas du tome 8 des Chevaliers, dont l'OCR a perdu le chapitre 1, ce qui
 * faisait rejeter les cinquante suivants. La sous-suite croissante absorbe les
 * titres manquants tout en écartant les nombres du texte.
 */
function longestIncreasing(cands: Candidate[]): Candidate[] {
  if (!cands.length) return [];
  const best = new Array(cands.length).fill(1);
  const prev = new Array(cands.length).fill(-1);
  let bestEnd = 0;

  for (let i = 0; i < cands.length; i++) {
    for (let j = 0; j < i; j++) {
      if (cands[j].number < cands[i].number && best[j] + 1 > best[i]) {
        best[i] = best[j] + 1;
        prev[i] = j;
      }
    }
    if (best[i] > best[bestEnd]) bestEnd = i;
  }

  const chain: Candidate[] = [];
  for (let i = bestEnd; i >= 0; i = prev[i]) {
    chain.push(cands[i]);
    if (prev[i] === -1) break;
  }
  return chain.reverse();
}

/**
 * Écarte les titres que l'OCR a détruits, sans écarter les titres simplement
 * rares.
 *
 * La rareté est un mauvais critère : « Le contrechoc », « Un sycophante » ou
 * « Rossolis » sont des titres valides dont les mots n'apparaissent presque
 * nulle part ailleurs dans la saga. Un titre cassé se reconnaît bien mieux à sa
 * forme — casse incohérente au milieu d'un mot, glyphes étrangers, mots sans
 * voyelle : « sIiLeENce », « La ¢orMULE MacGcique », « oes ».
 */
function titleIsReadable(title: string): boolean {
  const t = title.trim();
  if (t.length < 4) return false;

  const words = t.match(/[A-Za-zÀ-ÿŒœ’-]{2,}/g) ?? [];
  if (!words.length) return false;

  // Une minuscule suivie d'une majuscule à l'intérieur d'un mot ne se produit
  // pas en français : c'est la signature des petites capitales mal reconnues.
  const scrambled = words.filter((w) => /[a-zà-ÿ][A-ZÀ-Ý]/.test(w)).length;
  if (scrambled / words.length >= 0.3) return false;

  // Glyphes qui n'appartiennent pas à un titre.
  if (/[¢©|§~^*\\{}<>=+_]/.test(t)) return false;

  // Un mot français de trois lettres ou plus contient une voyelle.
  const long = words.filter((w) => w.length >= 3);
  const voiceless = long.filter((w) => !/[aeiouyàâäéèêëîïôöùûüÿœ]/i.test(w)).length;
  if (long.length && voiceless / long.length >= 0.5) return false;

  return true;
}

export function parseBook(
  book: Book,
  rawText: string,
  vocab: Map<string, number> | null = null,
): ParsedBook {
  const { lines } = toLines(rawText);
  const warnings: string[] = [];

  // Coupe la table des matières finale.
  let end = lines.length;
  for (let i = lines.length - 1; i > lines.length * 0.6; i--) {
    if (lettersOnly(lines[i].text) === "tabledesmatieres") { end = i; break; }
  }
  const body = lines.slice(0, end);
  const base = bodyIndent(body);

  const tops = pageTops(body);
  let chain = longestIncreasing(findHeadings(body, tops, base));
  // Trop peu de chapitres numérotés : le livre en emploie sans doute d'un autre
  // genre, comme « Abussos » et ses intitulés en capitales.
  if (chain.length < 5) {
    const unnumbered = findUnnumberedHeadings(body, tops);
    if (unnumbered.length > chain.length) chain = unnumbered;
  }
  const accepted = new Map<number, Candidate>();
  for (const c of chain) accepted.set(c.line, c);

  /*
   * Dernier recours : aucun chapitre reconnu.
   *
   * Le découpage s'appuie sur le premier titre pour écarter les pages
   * liminaires ; sans titre, `started` restait faux et le livre entier était
   * rejeté en silence — un demi-million de caractères disparus sans un mot.
   * C'est arrivé aux deux premiers tomes d'Antarès, dont les titres de chapitre
   * sont incrustés en image et n'existent donc pas dans la couche texte.
   *
   * Mieux vaut un livre sans découpage qu'un livre absent : les références de
   * page, elles, restent exactes et vérifiables.
   */
  const noChapters = chain.length === 0;

  const chapters: Chapter[] = [];
  const paragraphs: Paragraph[] = [];
  let started = false; // vrai dès le premier titre : coupe les pages liminaires

  let cur = "";
  let curPage = body[0]?.page ?? 1;

  // Série de prose en attente, tant que le début du roman n'est pas établi.
  let pending: { text: string; page: number }[] = [];

  const flush = () => {
    const text = mergeDropCap(cur.replace(/\s+/g, " ").trim());
    cur = "";

    if (noChapters && !started) {
      if (text.length >= PROSE_MIN) {
        pending.push({ text, page: curPage });
        if (pending.length >= PROSE_RUN) {
          started = true;
          // La série qui a déclenché le départ appartient au roman : on la garde.
          for (const p of pending) paragraphs.push({ ...p, chapter: -1 });
          pending = [];
        }
      } else {
        pending = []; // ligne courte : la série est rompue, c'était du liminaire
      }
      return;
    }

    // Sous 25 caractères c'est un résidu de mise en page, pas une phrase.
    if (started && text.length >= 25) {
      paragraphs.push({ text, page: curPage, chapter: chapters.length - 1 });
    }
  };

  const openChapter = (number: number | null, title: string, page: number) => {
    flush();
    const clean = title.replace(/\s+/g, " ").trim();
    const readable = titleIsReadable(clean);
    const label =
      number === null ? clean
      : readable ? `Chapitre ${number} — ${clean}`
      : `Chapitre ${number}`;
    chapters.push({ number, title: readable ? clean : "", rawTitle: clean, label });
    started = true;
    curPage = page;
  };

  for (let i = 0; i < body.length; i++) {
    const line = body[i];
    if (!line.text) { flush(); continue; }

    const heading = accepted.get(i);
    if (heading) { openChapter(heading.number, heading.title, heading.page); continue; }
    // Ligne du numéro seul dont le titre a déjà ouvert le chapitre.
    if (CHAP_NUM_ALONE.test(line.raw) && accepted.has(i + 1)) continue;

    if (FRONT_HEADING.test(line.text) || BACK_HEADING.test(line.text)) {
      openChapter(null, line.text.trim(), line.page);
      continue;
    }

    // Pages liminaires : remerciements, « Déjà parus »… On les saute en
    // attendant le premier titre — sauf s'il n'y en a aucun, auquel cas c'est
    // la longueur du premier paragraphe de prose qui donnera le départ.
    if (!started && !noChapters) continue;

    // — Corps de texte ————————————————————————————————
    // Un alinéa ouvre un paragraphe ; les répliques le sont aussi dans ces
    // éditions, elles n'ont donc pas besoin d'une règle propre.
    if (line.indent > base + 1) flush();

    // La page d'un paragraphe est celle où il commence — quel que soit ce qui
    // l'a ouvert. La rattacher au seul alinéa laissait à la page 1 tous les
    // paragraphes des livres qui séparent leurs paragraphes par une ligne vide
    // sans retrait : le tome III d'Ashur-Sîn citait ainsi 467 000 caractères
    // comme s'ils tenaient sur une seule page.
    if (!cur) curPage = line.page;

    cur = joinLine(cur, line.text, vocab);
  }
  flush();

  const id = bookId(book);
  const numbered = chapters.filter((c) => c.number !== null);
  if (noChapters) {
    warnings.push(
      `${id} : aucun titre de chapitre dans la couche texte — livre indexé d'un seul tenant, ` +
      `les références de page restent exactes`,
    );
  } else if (!numbered.length) {
    warnings.push(`${id} : aucun chapitre détecté`);
  }

  // Deux cas distincts, qu'il serait trompeur de confondre : une édition dont
  // les chapitres n'ont jamais eu de titre, et un titre que l'OCR a détruit.
  const untitled = numbered.filter((c) => !c.title && !c.rawTitle).length;
  const unreadable = numbered.filter((c) => !c.title && c.rawTitle).length;
  if (unreadable) {
    warnings.push(`${id} : ${unreadable}/${numbered.length} titres de chapitre illisibles (numéro conservé)`);
  }
  if (untitled === numbered.length && numbered.length) {
    warnings.push(`${id} : chapitres sans titre dans cette édition (numérotation seule)`);
  }

  return { book, chapters, paragraphs, warnings };
}

/** Vocabulaire des mots non coupés en fin de ligne, pour arbitrer les césures. */
export function collectVocab(rawTexts: string[]): Map<string, number> {
  const vocab = new Map<string, number>();
  for (const raw of rawTexts) {
    for (const line of raw.split("\n")) {
      const t = line.trim();
      if (!t) continue;
      // La dernière unité d'une ligne peut être coupée : on l'ignore.
      const words = t.split(/\s+/).slice(0, -1);
      for (const w of words) {
        const k = w.toLowerCase().replace(/^[^a-zà-ÿ-]+|[^a-zà-ÿ-]+$/gi, "");
        if (k.length >= 2) vocab.set(k, (vocab.get(k) ?? 0) + 1);
      }
    }
  }
  return vocab;
}
