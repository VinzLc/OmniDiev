# Wanda — sprite de personnage

> À jouer après avoir posé [le contexte](../CONTEXTE.md) dans la session.

*Fiche Codex : Chevalier femme et épouse de Falcon, elle devient mère de Nartrach puis d'Aurélys, et développe progressivement des dons de voyance qui la tourmentent.*

## Ce que le texte dit de son apparence

*Phrases relevées automatiquement dans les romans, la plus probante en tête. À peser :
l'extraction attribue parfois à un personnage ce que la phrase dit de son voisin.*

> « — Moi, c’est Wanda, annonça celle qui portait ses cheveux noirs très courts. »
>
> « Jamais Wanda n’avait vu un être humain d’une telle pâleur. »

## Ce qu'il faut produire

Une planche de sprites de **32×32 pixels par image**, disposée en
**4 colonnes × 4 rangées** (soit 128×128 px au total) :

- rangée 1 : marche de face (vers le joueur) — 4 images (repos, pas gauche, repos, pas droit)
- rangée 2 : marche de dos — 4 images (repos, pas gauche, repos, pas droit)
- rangée 3 : marche de profil gauche — 4 images (repos, pas gauche, repos, pas droit)
- rangée 4 : marche de profil droit — 4 images (repos, pas gauche, repos, pas droit)

## Style

- pixel art, style Game Boy Advance (2001-2005), vu du dessus en 3/4 comme Pokémon Rubis/Saphir
- palette limitée à 16 couleurs maximum, aplats francs, contour sombre net (pas d'anti-aliasing)
- ombrage à deux tons seulement : une couleur de base, une ombre — jamais de dégradé
- lisibilité à petite taille : les traits distinctifs doivent survivre à un affichage de 32 pixels

## À éviter

- pas de rendu 3D, pas de peinture numérique, pas de style anime moderne
- pas d'anti-aliasing, pas de dégradés, pas de flou
- pas de texte, pas de filigrane, pas de cadre
- pas de fond décoratif sur les sprites : fond strictement transparent

## Cohérence

C'est le point le plus fragile d'une génération. **Les seize images doivent montrer la même
personne** : même palette, même silhouette, mêmes proportions. Si l'outil dérive d'une
rangée à l'autre, générer d'abord la rangée « face », puis la fournir en référence pour les
trois autres plutôt que de tout demander d'un coup.

## Fichier attendu

`jeu/art/personnages/wanda.png` — fond transparent, PNG sans compression avec perte.
