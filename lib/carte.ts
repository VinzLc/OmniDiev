/**
 * Le continent d'Enkidiev, dessiné par calcul.
 *
 * Deux tentatives de le faire produire par l'IA graphique ont échoué : la
 * première a rendu un décor de canyon vu d'avion, la seconde un dessin au trait
 * presque blanc bordé d'un cadre qu'on avait explicitement interdit. Une carte
 * cartographique n'est pas une image de terrain, et le modèle ne fait pas la
 * différence.
 *
 * On la dessine donc, comme on dessine les arcs de taillade et les braises. Ce
 * qu'on y gagne dépasse la question du style : **les royaumes tombent
 * exactement là où le dessin les met**, puisque le dessin et leurs positions
 * sortent de la même grille. Une carte générée aurait demandé de placer les
 * marqueurs à l'œil par-dessus, et ils auraient dérivé à la première reprise.
 *
 * La géographie vient de la carte publiée de l'œuvre — la disposition des sept
 * royaumes est un fait qu'on peut relever. Le dessin, lui, est à nous : le
 * dépôt est public et l'illustration originale ne le sera pas.
 */

/** Un caractère par cellule. Trente-six rangées de soixante-quatre. */
const LEGENDE = {
  " ": "parchemin", // hors du monde
  "~": "mer",
  n: "neige",
  p: "plaine",
  f: "foret",
  d: "desert",
  m: "montagne",
} as const;

/* Le continent. L'ouest est découpé de baies profondes, l'est muré de
 * montagnes, le sud passe de la forêt au désert. Le nord se termine en plateau
 * de neige au-dessus des falaises. */
export const GRILLE = [
  "                                                                ",
  "                        ~~~~~~~~                                ",
  "                   ~~~~~nnnnnnnnnn~~~                           ",
  "                 ~~~~nnnnnnnnnnnnnnn~~~~                        ",
  "              ~~~~~nnnnnnnnnnnnnnnnnnn~~~~~mm                   ",
  "            ~~~~~nnnnnnnnnnnnnnnnnnnnnn~~~mmmm                  ",
  "          ~~~~~ppppppppnnnnnnnnnppppppp~~~mmmmm                 ",
  "         ~~~~pppppppppppppppppppppppppppmmmmmmmm                ",
  "        ~~~~ppppppppppppppppppppppppppppmmmmmmmmm               ",
  "       ~~~ppppppppppppppppppppppppppppppmmmmmmmmmm              ",
  "      ~~~pppppppppppppppppppppppppppppppmmmmmmmmmmm             ",
  "     ~~~ppppppppppppppppppppppppppppppppmmmmmmmmmmmm            ",
  "     ~~pppppppppppppppppppppppppppppppppmmmmmmmmmmmm            ",
  "    ~~~pppppppppppppppppppppppppppppppppmmmmmmmmmmmmm           ",
  "    ~~pppppppppppppppppppppppppppppppppppmmmmmmmmmmmm           ",
  "   ~~~ppppppppppppppppppppppppppppppppppmmmmmmmmmmmmmm          ",
  "   ~~pppppppppppppppppppppppppppppppppppmmmmmmmmmmmmmm          ",
  "  ~~~ppppppppppppppppppppppppppppppppppmmmmmmmmmmmmmmm          ",
  "  ~~pppppppppppppppppppppppppppppppppppmmmmmmmmmmmmmmm          ",
  "  ~~ppppppppppppppppppppppppppppppppppmmmmmmmmmmmmmmmm          ",
  "  ~~~pppppppppppppppppppppppppppppppppmmmmmmmmmmmmmmm           ",
  "   ~~ppppppppppppppppppppppppppppppppmmmmmmmmmmmmmmmm           ",
  "   ~~~pppppppppppppppppppppppfffffffpmmmmmmmmmmmmmmm            ",
  "    ~~ppppppppppppppppppppffffffffffffmmmmmmmmmmmmm             ",
  "    ~~~pppppppppppppppppffffffffffffffmmmmmmmmmmmm              ",
  "     ~~~pppppppppppppppfffffffffffffffmmmmmmmmmmm               ",
  "      ~~~ppppppppppppffffffffffffffffmmmmmmmmmmm                ",
  "       ~~~pppppppppdddffffffffffffffmmmmmmmmmm                  ",
  "        ~~~ppppppdddddddddffffffffmmmmmmmmmm                    ",
  "         ~~~pppdddddddddddddddddmmmmmmmmm                       ",
  "          ~~~dddddddddddddddddddmmmmmmm                         ",
  "           ~~~ddddddddddddddddddmmmmm                           ",
  "            ~~~dddddddddddddddddmmm                             ",
  "             ~~~~ddddddddddddddd                                ",
  "                ~~~~ddddddddd                                   ",
  "                                                                ",
];

export const CELLULE = 5; // pixels par cellule → 320×180
export const LARGEUR = GRILLE[0].length * CELLULE;
export const HAUTEUR = GRILLE.length * CELLULE;

/**
 * Les couleurs, prises dans la palette du monde.
 *
 * Nommées `COULEURS` et non `TEINTES` : `build-jeu-donnees` porte déjà un
 * `TEINTES` — les teintes de silhouette — et l'import s'est fait écraser en
 * silence. Le dépouillement de types de Node ne signale pas une double
 * déclaration, alors le tableau de chaînes a pris la place du dictionnaire de
 * couleurs et le dessin est tombé sur « teinte is not iterable ». Deux noms
 * identiques dans deux fichiers qui se rencontrent est une faute qui ne se voit
 * qu'à l'exécution.
 *
 * Le parchemin et la mer sortent du registre des neutres et des froids ; la
 * plaine et la forêt des verts de l'Ordre ; le désert et la montagne des ors et
 * des pierres. Aucune teinte inventée : une carte qui jurerait avec le jeu se
 * lirait comme un écran emprunté ailleurs.
 */
export const COULEURS: Record<string, [number, number, number]> = {
  parchemin: [0x22, 0x22, 0x2c],
  mer: [0x2d, 0x5f, 0xa8],
  neige: [0xe3, 0xf3, 0xfe],
  plaine: [0x1c, 0x7a, 0x4e],
  foret: [0x0f, 0x38, 0x26],
  desert: [0xc0, 0x8f, 0x34],
  montagne: [0x71, 0x72, 0x7e],
  cote: [0x0b, 0x0a, 0x10],
};

/** Ce que porte une cellule, en clair. */
export function terrain(x: number, y: number): string {
  const l = GRILLE[y];
  if (!l || x < 0 || x >= l.length) return "parchemin";
  return LEGENDE[l[x] as keyof typeof LEGENDE] ?? "parchemin";
}

/**
 * Les lieux jouables, à leur place sur la grille.
 *
 * `salle` est la pièce où l'on débarque. Le chapitre en cours peut la
 * remplacer : arriver en Émeraude alors que le chapitre s'ouvre dans la
 * bibliothèque doit déposer dans la bibliothèque, sans quoi il faudrait
 * traverser le Château à pied après chaque voyage.
 */
export type Escale = { lieu: string; nom: string; x: number; y: number; salle: string };

export const ESCALES: Escale[] = [
  { lieu: "shola", nom: "Shola", x: 28, y: 4, salle: "palais-de-glace" },
  { lieu: "royaume-d-opale", nom: "Opale", x: 36, y: 10, salle: "frontiere-d-opale" },
  { lieu: "chateau-d-emeraude", nom: "Émeraude", x: 24, y: 16, salle: "salle-du-trone" },
  { lieu: "royaume-de-rubis", nom: "Rubis", x: 35, y: 17, salle: "chateau-de-rubis" },
  { lieu: "royaume-de-jade", nom: "Jade", x: 33, y: 21, salle: "voie-de-jade" },
  // Zénor est une grève : sa marque doit toucher la mer, non flotter dans les
  // terres. Une escale mal posée ne casse rien et ment sur la géographie.
  { lieu: "zenor", nom: "Zénor", x: 6, y: 20, salle: "greve-de-zenor" },
  { lieu: "foret", nom: "Forêt des Elfes", x: 30, y: 25, salle: "foret-des-elfes" },
];
