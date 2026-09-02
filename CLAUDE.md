# OmniDiev

Deux ouvrages sur le même corpus : **l'Oracle**, qui répond à toute question sur les
44 volumes d'Anne Robillard, et **le jeu**, un RPG en pixel art où l'on incarne Wellan.

Tout est écrit en français — code, commentaires, messages de commit, interface. Les
commentaires disent **pourquoi**, jamais quoi : le code dit déjà quoi.

## Ce qui casse pour de bon

Quatre règles dont la violation ne se rattrape pas.

**Les romans ne quittent pas la machine.** Œuvres sous droits. `.gitignore` porte `Epop*/`
— le motif couvre les épopées à venir ; n'en nommer qu'une les laisserait passer.

**L'index de recherche non plus.** `data/index/chunks.json` contient le texte intégral des
44 volumes. `scripts/build-site.ts` refuse de publier s'il trouve `chunks.json`, `bm25.json`
ou `embeddings.bin` dans `out/` — ne pas contourner ce refus.

**Les clés vivent dans `.env.local`**, ignoré par git : `ANTHROPIC_API_KEY`,
`PIXELLAB_API_KEY`. Ne jamais les faire apparaître dans une sortie, un commit, une
conversation.

**PixelLab facture à la génération.** Sonder une direction avant d'en engager quatre. Le
mode `pro` consomme vingt à quarante générations *par direction*.

## Source unique de vérité

`lib/books.ts` porte les 44 volumes, leur ordre absolu de lecture et leur qualité de
numérisation. Aucun décompte ne se code en dur ailleurs — l'interface a déjà menti trois
fois pour cette raison.

`jeu/art/CONTEXTE.md` porte la palette du monde. Elle est **lue** par `art-normalise`, pas
recopiée : deux exemplaires divergeraient sans que personne le voie.

La **carte du continent** se dessine par calcul depuis `lib/carte.ts` : l'illustration
publiée est sous droits et le dépôt est public. Le dessin et la place des royaumes
sortent de la même grille — deux sources auraient dérivé.

Une **porte** ne porte pas de nom : elle dit vers quelle salle elle mène, et l'invite lit le
`nom` de celle-ci chez elle. Deux exemplaires d'un même nom divergent sans qu'on le voie.

`ordered()` dans `lib/codex-view.ts` fixe l'ordre des fiches, donc leur numéro. Il est exporté
et lu par `build-jeu-donnees.ts` : « N° 062 » désigne Wellan sur le site comme dans le Codex
du jeu.

## Les commandes

| | |
|---|---|
| `npm run ingest` | PDF → texte → fragments → plongements |
| `npm run codex` | fiches, généalogies, pages |
| `npm run doctor` | état de l'index |
| `npm run dev` | l'Oracle en local |
| `npm run site` | export statique dans `out/`, contrôle compris |
| `npm run deploy` | publication GitHub Pages (Codex et Généalogie seuls) |
| `npm run jeu` | le jeu, écran-titre compris |
| `npm run jeu:donnees` | Codex → `monde.json`, salles, effets, bruitages |
| `npm run jeu:chapitres` | un chapitre, ou tous, sans fenêtre — six secondes pièce |
| `npm run art` | rédige les commandes d'images |
| `npm run art:generer` | les joue via l'API PixelLab |
| `npm run art:normalise` | rendu brut → planche pour Godot |
| `npm run art:expressions` | décline les humeurs d'un portrait |
| `npm run art:verifier` | contrôle mécanique des images |

Trois compétences prennent le relais : **atelier-graphique** pour les images,
**jeu-godot** pour le jeu, **oracle-site** pour l'Oracle et ce qui se publie.

## Le motif qui revient

L'ennemi de ce projet n'est pas l'erreur, c'est la **dégradation silencieuse**. Des livres
perdus sans avertissement, un cache vide pris pour un succès, un résultat partiel écrasant
un complet, un rejet erroné supprimant un fait vrai, un sprite au visage vert déclaré
conforme.

D'où la règle générale : **une opération qui produit moins qu'avant doit refuser, pas
écraser.** Et ce qu'une machine ne peut pas juger, il faut le regarder.
