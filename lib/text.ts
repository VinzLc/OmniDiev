/** Normalisation partagée par l'indexation et l'interrogation. */

const STOPWORDS = new Set(`
a ai aie ait alors as au aucun aucune aujourd auquel aura aurai auraient aurait
aurez auront aussi autre autres aux avaient avait avant avec avez aviez avoir
avons ayant beaucoup bien c car ce ceci cela celle celles celui cent cependant
certain certaine certains ces cet cette ceux chaque chez ci comme comment d dans
de dedans dehors deja depuis des desormais deux devrait doit donc dont du duquel
durant elle elles en encore enfin entre est et etaient etait etant etc ete etes
etre eu eux fait faire fois font furent hors ici il ils j je juste l la laquelle
le lequel les lesquelles lesquels leur leurs lors lorsque lui m ma mais malgre me
meme memes mes mien moi moins mon n ne ni non nos notre nous nul on ont or ou ou
oui par parce parmi pas pendant peu peut peuvent plus plusieurs plutot pour
pourquoi pourtant pouvait pu puis puisque qu quand que quel quelle quelles quels
qui quoi s sa sans se sera serait ses si sien soit son sont sous soyez suis sur
t ta tandis tant te tel telle tes toi ton tous tout toute toutes tres trop tu un
une vers voici voila vos votre vous y etre avoir cela ceux-ci celui-ci
`.trim().split(/\s+/));

const deaccent = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");

/**
 * Réduit une forme fléchie à une racine approchée.
 *
 * Volontairement timide : dans cette saga l'essentiel des requêtes porte sur des
 * noms propres (« Onyx », « Enkidiev », « Amecareth »), qu'une racinisation
 * agressive mutilerait. On ne traite donc que le pluriel régulier en -s, et
 * jamais le -x, qui appartient à des noms propres autant qu'à des pluriels.
 */
function stem(w: string): string {
  if (w.length > 4 && w.endsWith("s") && !w.endsWith("ss")) return w.slice(0, -1);
  return w;
}

export function tokenize(text: string): string[] {
  const out: string[] = [];
  for (const raw of deaccent(text.toLowerCase()).split(/[^a-z0-9]+/)) {
    if (raw.length < 2) continue;
    if (STOPWORDS.has(raw)) continue;
    out.push(stem(raw));
  }
  return out;
}

/** Clé de comparaison insensible à la casse et aux accents. */
export function fold(s: string): string {
  return deaccent(s.toLowerCase()).replace(/[^a-z0-9]+/g, " ").trim();
}
