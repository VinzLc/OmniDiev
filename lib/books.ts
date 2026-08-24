/**
 * Catalogue des sources.
 *
 * Les épopées se suivent dans le même univers : « Les Héritiers d'Enkidiev »
 * reprend là où « Les Chevaliers d'Émeraude » s'arrête, avec les mêmes
 * personnages. Elles forment donc un seul corpus interrogeable, et non deux
 * bots séparés — une question sur Onyx doit pouvoir traverser les vingt-quatre
 * tomes.
 *
 * `order` porte cette continuité : c'est la position absolue d'un tome dans la
 * chronologie de lecture. La recherche, le filtrage anti-divulgation et le tri
 * s'appuient dessus, jamais sur le couple (saga, tome).
 */

export type Saga = {
  id: number;
  name: string;
  /**
   * Nom court et distinctif, pour les colonnes étroites.
   * Surtout pas le premier mot du titre : « Les Chevaliers d'Émeraude » et
   * « Les Chevaliers d'Antarès » donneraient tous deux « Chevaliers ».
   */
  short: string;
  /** Dossier des PDF, relatif à la racine du projet. */
  dir: string;
};

export type Book = {
  saga: number;
  /** Numéro du tome dans sa saga. `0` désigne un hors-série. */
  tome: number;
  /** Position absolue dans la chronologie, 1 à 24. */
  order: number;
  title: string;
  year: number;
  /** Nom du fichier dans le dossier de la saga. */
  source: string;
  /**
   * Qualité de la couche texte.
   * `scan` déclenche la passe de réparation OCR de lib/ocr-repair.ts.
   */
  quality: "clean" | "scan";
};

export const SAGAS: Saga[] = [
  { id: 1, name: "Les Chevaliers d'Émeraude", short: "Émeraude", dir: "Epopée1" },
  { id: 2, name: "Les Héritiers d'Enkidiev", short: "Héritiers", dir: "Epopée2" },
  { id: 3, name: "Les Chevaliers d'Antarès", short: "Antarès", dir: "Epopée3" },
  { id: 4, name: "Légendes d'Ashur-Sîn", short: "Ashur-Sîn", dir: "Epopée4" },
];

export const AUTHOR = "Anne Robillard";

/** Saga 1 — Les Chevaliers d'Émeraude (2002-2008). */
const SAGA1: Omit<Book, "order">[] = [
  { saga: 1, tome: 1, title: "Le Feu dans le ciel", year: 2002, quality: "clean",
    source: "Robillard,Anne-[Les Chevaliers d'Emeraude-01]Le Feu dans le ciel.(2003).OCR. by k10.pdf" },
  { saga: 1, tome: 2, title: "Les Dragons de l'Empereur Noir", year: 2003, quality: "clean",
    source: "Robillard,Anne-[Les Chevaliers d'Emeraude-02]Les dragons de l'empereur noir(2003).OCR.by k10.pdf" },
  { saga: 1, tome: 3, title: "Piège au Royaume des Ombres", year: 2003, quality: "clean",
    source: "Robillard,Anne-[Les Chevaliers d'Emeraude-03]Piège au royaume des Ombres(2003).OCR.by k10.pdf" },
  { saga: 1, tome: 4, title: "La Princesse rebelle", year: 2004, quality: "clean",
    source: "Robillard,Anne-[Les Chevaliers d'Emeraude-04]La Princesse Rebelle(2004).OCR.French.by k10.pdf" },
  { saga: 1, tome: 5, title: "L'Île des Lézards", year: 2004, quality: "clean",
    source: "Robillard,Anne-[Les Chevaliers d'Emeraude-05]L'ile des lezards(2004).French.by k10.pdf" },
  { saga: 1, tome: 6, title: "Le Journal d'Onyx", year: 2005, quality: "clean",
    source: "Le Journal d'Onyx -- Robillard, Anne -- Les Chevaliers d'Emeraude-06, 2005 -- 98274a9d761478e316005a91110ac5b6 -- Anna’s Archive.pdf" },
  { saga: 1, tome: 7, title: "L'Enlèvement", year: 2005, quality: "clean",
    source: "L'Enlevement -- Robillard, Anne -- Les Chevaliers d'Emeraude-07, 2005 -- c63b9de42ef16e947c4b125b57311207 -- Anna’s Archive.pdf" },
  { saga: 1, tome: 8, title: "Les Dieux déchus", year: 2005, quality: "scan",
    source: "annas-arch-df258544330f.pdf" },
  { saga: 1, tome: 9, title: "L'Héritage de Danalieth", year: 2006, quality: "clean",
    source: "L'héritage de Danalieth (Les Chevaliers d'Emeraude 9) -- Robillard, Anne -- Les Chevaliers d'Emeraude-09, 2006 -- Michel Lafon -- isbn13 9782749911052 -- c7affc32a51a035b741e1d558695d7cc -- Anna’s Archive.pdf" },
  { saga: 1, tome: 10, title: "Représailles", year: 2007, quality: "clean",
    source: "Représailles (Les Chevaliers d'Emeraude 10) -- Robillard, Anne -- Les Chevaliers d'Emeraude-10, 2007 -- Michel Lafon -- isbn13 9782749911540 -- 1258f26c7686e7f798f67a8ce0f95a8c -- Anna’s Archive.pdf" },
  { saga: 1, tome: 11, title: "La Justice céleste", year: 2007, quality: "clean",
    source: "La Justice Celeste -- Robillard, Anne -- Les Chevaliers d'Emeraude-11, 2007 -- 6db771c34681dc637938ef67ed18d7d6 -- Anna’s Archive.pdf" },
  { saga: 1, tome: 12, title: "Irianeth", year: 2008, quality: "clean",
    source: "Irianeth -- Robillard, Anne -- Les Chevaliers d'Emeraude-12, 2008 -- 04faffdeaabf52cda6650c542ff32f3c -- Anna’s Archive.pdf" },

  // Préquel paru quinze ans après le tome I : il raconte la jeunesse d'Onyx et
  // la fondation du premier Ordre. Placé ici, en ordre de publication, il reste
  // hors de portée d'un lecteur en cours de saga — il dévoilerait d'un coup ce
  // que les douze tomes révèlent peu à peu.
  { saga: 1, tome: 0, title: "Les premiers Chevaliers", year: 2023, quality: "clean",
    source: "[Les Chevaliers d'Emeraude 0] Robillard Anne - Les premiers Chevaliers (2023, Wellan Inc.) - libgen.li.pdf" },
];

/** Saga 2 — Les Héritiers d'Enkidiev (2011-2015). */
const SAGA2: Omit<Book, "order">[] = [
  { saga: 2, tome: 1, title: "Renaissance", year: 2011, quality: "scan",
    source: "Les HÃ©ritiers d'Enkidiev, Tome 1 (French Edition) -- Anne Robillard -- Les héritiers d'Enkidiev, Neuilly-sur-Seine, DL 2011 -- Michel Lafon -- isbn13 9782749913957 -- 878003bb6f309cb442336a96a4361543 -- Anna’s Archive.pdf" },
  { saga: 2, tome: 2, title: "Nouveau monde", year: 2011, quality: "scan",
    source: "annas-arch-ab5e91641add.pdf" },
  { saga: 2, tome: 3, title: "Les Dieux ailés", year: 2012, quality: "scan",
    source: "isbn_9782749916125 -- Author Unknown -- None -- MICHEL LAFON -- isbn13 9782749913957 -- 24c902fa141368b0b1d252dd756369e5 -- Anna’s Archive.pdf" },
  { saga: 2, tome: 4, title: "Le Sanctuaire", year: 2012, quality: "scan",
    source: "Les Héritiers d'Enkidiev - tome 4 Le sanctuaire (4) (French -- Robillard, Anne -- Les héritiers d'Enkidiev _ Anne Robillard, Paris, 2014 -- MICHEL -- isbn13 9782749913957 -- c99fa71f34a1eb89f16b3f90187b4bb2 -- Anna’s Archive.pdf" },
  { saga: 2, tome: 5, title: "Abussos", year: 2012, quality: "clean",
    source: "Abussos -- Robillard,Anne -- Les Heritiers d'Enkidiev 5, 2012 -- 436592c881854688284a36e0900c011b -- Anna’s Archive.pdf" },
  { saga: 2, tome: 6, title: "Nemeroff", year: 2012, quality: "scan",
    source: "isbn_9782749919751 -- Unknown -- 2012 -- MICHEL LAFON -- isbn13 9782749913957 -- 549b4907f9f65670adaf71c2188512f5 -- Anna’s Archive.pdf" },
  { saga: 2, tome: 7, title: "Le Conquérant", year: 2013, quality: "scan",
    source: "Les Héritiers d'Enkidiev - tome 7 Le conquérant (7) (French -- Author Unknown -- Les héritiers d'Enkidiev _ Anne Robillard, -- MICHEL LAFON -- isbn13 9782749913957 -- b1dced18a301e0ba72ff8132e858d1ee -- Anna’s Archive.pdf" },
  { saga: 2, tome: 8, title: "An-Anshar", year: 2013, quality: "scan",
    source: "Les Héritiers d'Enkidiev - tome 8 An-Anshar (French Edition) -- Anne Robillard -- Les héritiers d'Enkidiev, tome 8, Neuilly-sur-Seine, DL -- MICHEL -- isbn13 9782749913957 -- b3b7020e787ae261c3c1c64fc80de56e -- Anna’s Archive.pdf" },
  { saga: 2, tome: 9, title: "Mirages", year: 2013, quality: "clean",
    source: "Les heritiers d'Enkidiev_ Tome 9, Mirages -- Robillard, Anne, 1955- -- De Marque, Inc_, [Mont-Saint-Hilaire, QC], 2015 -- [Mont-Saint-Hilaire, QC] _ -- isbn13 9782923925028 -- 11867996f04b78894600e0e057f4d739 -- Anna’s Archive.pdf" },
  { saga: 2, tome: 10, title: "Déchéance", year: 2014, quality: "clean",
    source: "[Les Héritiers d'Enkidiev 10 ] Robillard, Anne - Déchéance (2014, Wellan) - libgen.li.pdf" },
  { saga: 2, tome: 11, title: "Double allégeance", year: 2014, quality: "scan",
    source: "Les Héritiers d'Enkidiev - tome 11 Double allégeance (French -- Unknown -- Volume 2, 2015 -- French and European Publications Inc -- isbn13 9782749927251 -- c5667f2fba3036eb9833e00fea24de65 -- Anna’s Archive.pdf" },
  { saga: 2, tome: 12, title: "Kimaati", year: 2015, quality: "clean",
    source: "[Les Héritiers d'Enkidiev 12 ] Robillard, Anne - Les Heritiers d'Enkidiev (2015, Wellan) - libgen.li.pdf" },
];

/** Saga 3 — Les Chevaliers d'Antarès (2016-2019). */
const SAGA3: Omit<Book, "order">[] = [
  { saga: 3, tome: 1, title: "Descente aux enfers", year: 2016, quality: "clean",
    source: "[Les Chevaliers d&_039_Antarès - Les Chevaliers d&_039_Antarès] Les chevaliers d&_039_Antarès. Tome 1, Descente aux enfers{Anne Robillard}(2016, Wellan inc.){115981922} libgen.li.pdf" },
  { saga: 3, tome: 2, title: "Basilics", year: 2016, quality: "clean",
    source: "[Les Chevaliers d'Antares 2] Robillard, Anne - Basilics (2016, Wellan) - libgen.li.pdf" },
  { saga: 3, tome: 3, title: "Manticores", year: 2017, quality: "clean",
    source: "[Les Chevaliers d'Antarès 03] Robillard, Anne - Manticores (WELLAN) - libgen.li.pdf" },
  { saga: 3, tome: 4, title: "Chimères", year: 2017, quality: "clean",
    source: "[Les Chevaliers d'Antarès 04] Robillard, Anne - Chimères (WELLAN) - libgen.li.pdf" },
  { saga: 3, tome: 5, title: "Salamandres", year: 2017, quality: "clean",
    source: "[Les Chevaliers d'Antarès 05] Robillard, Anne - Salamandres (WELLAN) - libgen.li.pdf" },
  { saga: 3, tome: 6, title: "Les Sorciers", year: 2017, quality: "clean",
    source: "[Les Chevaliers d'Antarès 06] Anne Robillard - Les sorciers (Wellan) - libgen.li.pdf" },
  { saga: 3, tome: 7, title: "Vent de trahison", year: 2017, quality: "clean",
    source: "[Les Chevaliers d'Antarès _7] Robillard, Anne - Vent de trahison (2017, Wellan) - libgen.li.pdf" },
  { saga: 3, tome: 8, title: "Porteur d'espoir", year: 2018, quality: "clean",
    source: "[Les Chevaliers d'Antarès 08] Anne Robillard - Porteur d'espoir (2018, Wellan) - libgen.li.pdf" },
  { saga: 3, tome: 9, title: "Justiciers", year: 2019, quality: "clean",
    source: "[Les Chevaliers d'Antarès 09] - Justiciers (2019, Wellan) - libgen.li.pdf" },
  { saga: 3, tome: 10, title: "La Tourmente", year: 2019, quality: "clean",
    source: "[Les Chevaliers d'Antarès 10] - La tourmente (2019, Wellan) - libgen.li.pdf" },
  { saga: 3, tome: 11, title: "Alliance", year: 2019, quality: "clean",
    source: "[Les Chevaliers d'Antarès 11] - Alliance (2019, Wellan) - libgen.li.pdf" },
  { saga: 3, tome: 12, title: "La Prophétie", year: 2019, quality: "clean",
    source: "[Les Chevaliers d'Antarès 12] - La prophétie (2019, Wellan) - libgen.li.pdf" },
];

/** Saga 4 — Légendes d'Ashur-Sîn (2021-2022), sept tomes. */
const SAGA4: Omit<Book, "order">[] = [
  { saga: 4, tome: 1, title: "Aranéa", year: 2021, quality: "clean",
    source: "[Légendes d'Ashur-Sîn _1] Robillard, Anne - Aranéa (2021, Wellan Inc) - libgen.li.pdf" },
  { saga: 4, tome: 2, title: "Azakhou", year: 2021, quality: "clean",
    source: "[Les légendes d'Ashur-Sîn 02] - Azakhou (2021, Wellan Inc) - libgen.li.pdf" },
  { saga: 4, tome: 3, title: "Dingirsigs", year: 2021, quality: "clean",
    source: "[Légendes d'Ashur-Sîn, tome 3] - Dingirsigs (2021, Wellan Inc) - libgen.li.pdf" },
  { saga: 4, tome: 4, title: "Antoum", year: 2021, quality: "clean",
    source: "[Légendes d'Ashur-Sîn 04] Anne Robillard - Antoum (2021, Wellan Inc) - libgen.li.pdf" },
  { saga: 4, tome: 5, title: "Naroux", year: 2022, quality: "clean",
    source: "Anne Robillard - Légendes d'Ashur-Sîn T5_ Naroux (2022, Wellan Inc.) - libgen.li.pdf" },
  { saga: 4, tome: 6, title: "Cinn", year: 2022, quality: "clean",
    source: "[Légendes d&_039_Ashur-Sîn 6 - Légendes d&_039_Ashur-Sîn 6] Cinn{Robillard, Anne}(2022, Wellan Inc.){113253888} libgen.li.pdf" },
  { saga: 4, tome: 7, title: "Naja", year: 2022, quality: "clean",
    source: "[Légendes d&_039_Ashur-Sîn 7 - Légendes d&_039_Ashur-Sîn 7] Naja{Anne Robillard}(2022, Wellan Inc.){112788405} libgen.li.pdf" },
];

export const BOOKS: Book[] = [...SAGA1, ...SAGA2, ...SAGA3, ...SAGA4].map((b, i) => ({ ...b, order: i + 1 }));

export const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];

export function sagaOf(id: number): Saga {
  const s = SAGAS.find((x) => x.id === id);
  if (!s) throw new Error(`Saga inconnue : ${id}`);
  return s;
}

export function bookAt(order: number): Book {
  const b = BOOKS.find((x) => x.order === order);
  if (!b) throw new Error(`Aucun tome à la position ${order}`);
  return b;
}

export function booksOfSaga(id: number): Book[] {
  return BOOKS.filter((b) => b.saga === id);
}

/** Vrai pour un hors-série, que sa numérotation ne situe pas dans la série. */
export function isCompanion(b: Pick<Book, "tome">): boolean {
  return b.tome === 0;
}

/** Identifiant court et stable d'un tome, ex. « E2T07 », « E1T00 ». */
export function bookId(b: Pick<Book, "saga" | "tome">): string {
  return `E${b.saga}T${String(b.tome).padStart(2, "0")}`;
}

/** Libellé d'un tome, ex. « Les Héritiers d'Enkidiev, tome VII — Le Conquérant ». */
export function bookLabel(b: Book): string {
  const saga = sagaOf(b.saga).name;
  if (isCompanion(b)) return `${saga}, hors-série — ${b.title}`;
  return `${saga}, tome ${ROMAN[b.tome]} — ${b.title}`;
}

/** Libellé compact pour l'interface, ex. « Héritiers VII ». */
export function shortLabel(b: Book): string {
  const s = sagaOf(b.saga).short;
  return isCompanion(b) ? `${s} hors-série` : `${s} ${ROMAN[b.tome]}`;
}
