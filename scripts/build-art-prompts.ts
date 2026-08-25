/**
 * Rédige les commandes d'images à jouer dans une IA générative spécialisée.
 *
 * Le contenu vient de deux sources, jamais de l'invention : la fiche du Codex
 * pour le rôle, et les phrases des romans pour l'apparence. La contrainte
 * technique, elle, est fixe — c'est elle qui rend les images utilisables dans
 * Godot, et cohérentes entre elles.
 *
 * Usage :
 *   npm run art -- --perso wellan --perso kira
 *   npm run art -- --lieu chateau-d-emeraude
 *   npm run art -- --lot etape0
 *
 * Sortie : jeu/art/commandes/<id>.md
 */
import fs from "node:fs";
import path from "node:path";
import { loadCodex, type CodexEntry } from "../lib/codex.ts";
import { appearanceOf, placeOf } from "../lib/appearance.ts";
import { fold } from "../lib/text.ts";

const ROOT = path.resolve(import.meta.dirname, "..");
const OUT = path.join(ROOT, "jeu", "art", "commandes");

/* ── Spécification technique ──────────────────────────────────────────────
 * Ces chiffres ne se négocient pas d'une image à l'autre : c'est ce qui fait
 * qu'un sprite entre dans la grille et qu'un décor s'aboute au suivant.
 */
const SPEC = {
  tile: 16,
  sprite: 32,
  frames: 4,
  directions: ["face (vers le joueur)", "dos", "profil gauche", "profil droit"],
  portrait: 96,
};

/** Ancrage stylistique, identique dans chaque commande. */
const STYLE = [
  "pixel art, style Game Boy Advance (2001-2005), vu du dessus en 3/4 comme Pokémon Rubis/Saphir",
  "palette limitée à 16 couleurs maximum, aplats francs, contour sombre net (pas d'anti-aliasing)",
  "ombrage à deux tons seulement : une couleur de base, une ombre — jamais de dégradé",
  "lisibilité à petite taille : les traits distinctifs doivent survivre à un affichage de 32 pixels",
].join("\n- ");

const NEGATIVE = [
  "pas de rendu 3D, pas de peinture numérique, pas de style anime moderne",
  "pas d'anti-aliasing, pas de dégradés, pas de flou",
  "pas de texte, pas de filigrane, pas de cadre",
  "pas de fond décoratif sur les sprites : fond strictement transparent",
].join("\n- ");

type Kind = "perso" | "lieu";

function quotes(list: { text: string }[]): string {
  if (!list.length) return "_Le texte ne décrit pas explicitement cette entité — inventer avec sobriété, dans l'esprit du reste._";
  return list.map((t) => `> « ${t.text} »`).join("\n>\n");
}

function personPrompt(e: CodexEntry): string {
  const traits = appearanceOf(e.name, e.aliases, 4);

  return `# ${e.name} — sprite de personnage

*Fiche Codex : ${e.gloss}*

## Ce que le texte dit de son apparence

*Phrases relevées automatiquement dans les romans, la plus probante en tête. À peser :
l'extraction attribue parfois à un personnage ce que la phrase dit de son voisin.*

${quotes(traits)}

## Ce qu'il faut produire

Une planche de sprites de **${SPEC.sprite}×${SPEC.sprite} pixels par image**, disposée en
**${SPEC.frames} colonnes × 4 rangées** (soit ${SPEC.sprite * SPEC.frames}×${SPEC.sprite * 4} px au total) :

${SPEC.directions.map((d, i) => `- rangée ${i + 1} : marche de ${d} — ${SPEC.frames} images (repos, pas gauche, repos, pas droit)`).join("\n")}

## Style

- ${STYLE}

## À éviter

- ${NEGATIVE}

## Cohérence

C'est le point le plus fragile d'une génération. **Les seize images doivent montrer la même
personne** : même palette, même silhouette, mêmes proportions. Si l'outil dérive d'une
rangée à l'autre, générer d'abord la rangée « face », puis la fournir en référence pour les
trois autres plutôt que de tout demander d'un coup.

## Fichier attendu

\`jeu/art/personnages/${e.id}.png\` — fond transparent, PNG sans compression avec perte.
`;
}

function placePrompt(e: CodexEntry): string {
  const traits = placeOf(e.name, 4);

  return `# ${e.name} — jeu de tuiles

*Fiche Codex : ${e.gloss}*

## Ce que le texte dit du lieu

*Phrases relevées automatiquement dans les romans, la plus probante en tête.*

${quotes(traits)}

## Ce qu'il faut produire

Un jeu de tuiles de **${SPEC.tile}×${SPEC.tile} pixels**, sur une planche de 16 colonnes,
comprenant au minimum :

- sols : dalle, terre battue, herbe, tapis
- murs : face, angles intérieurs et extérieurs, base et sommet
- ouvertures : porte fermée, porte ouverte, fenêtre, escalier montant et descendant
- mobilier : table, banc, coffre, torche murale, bannière

## Style

- ${STYLE}

## À éviter

- ${NEGATIVE}

## Raccord

**Chaque tuile de sol et de mur doit s'abouter à elle-même sans couture visible**, en
horizontal comme en vertical. Une tuile qui ne se répète pas proprement est inutilisable :
c'est la contrainte à vérifier avant tout le reste.

## Fichier attendu

\`jeu/art/lieux/${e.id}.png\` — fond transparent pour les tuiles ajourées.
`;
}

/** Lot minimal de l'étape 0 : de quoi faire marcher quelqu'un dans une salle. */
const LOTS: Record<string, { perso: string[]; lieu: string[] }> = {
  etape0: { perso: ["wellan", "emeraude-ier"], lieu: ["chateau-d-emeraude"] },
};

function main() {
  const l = loadCodex();
  if (!l) {
    console.error("Codex absent. Lancez d'abord : npm run codex");
    process.exit(1);
  }

  const argv = process.argv.slice(2);
  const collect = (flag: string) =>
    argv.reduce<string[]>((acc, a, i) => (a === flag && argv[i + 1] ? [...acc, argv[i + 1]] : acc), []);

  let persos = collect("--perso");
  let lieux = collect("--lieu");
  for (const name of collect("--lot")) {
    const lot = LOTS[name];
    if (!lot) { console.error(`Lot inconnu : ${name}. Connus : ${Object.keys(LOTS).join(", ")}`); process.exit(1); }
    persos = [...persos, ...lot.perso];
    lieux = [...lieux, ...lot.lieu];
  }

  if (!persos.length && !lieux.length) {
    console.error("Rien à produire. Exemple : npm run art -- --lot etape0");
    process.exit(1);
  }

  fs.mkdirSync(OUT, { recursive: true });
  const byId = new Map(l.codex.entries.map((e) => [e.id, e]));
  const byName = new Map(l.codex.entries.map((e) => [fold(e.name), e]));
  const find = (key: string) => byId.get(key) ?? byName.get(fold(key));

  let written = 0;
  const missing: string[] = [];

  for (const [kind, ids] of [["perso", persos], ["lieu", lieux]] as [Kind, string[]][]) {
    for (const id of ids) {
      const e = find(id);
      if (!e) { missing.push(id); continue; }
      const body = kind === "perso" ? personPrompt(e) : placePrompt(e);
      fs.writeFileSync(path.join(OUT, `${e.id}.md`), body);
      const traits = kind === "perso" ? appearanceOf(e.name, e.aliases, 4) : placeOf(e.name, 4);
      console.log(`  ${e.name.padEnd(24)} ${traits.length} phrase(s) du texte → ${e.id}.md`);
      written++;
    }
  }

  console.log(`\n${written} commandes dans ${path.relative(ROOT, OUT)}/`);
  if (missing.length) console.error(`Introuvables au Codex : ${missing.join(", ")}`);
}

main();
