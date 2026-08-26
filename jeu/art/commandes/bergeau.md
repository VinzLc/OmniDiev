# Bergeau — sprite de personnage

> À jouer après avoir posé [le contexte](../CONTEXTE.md) dans la session.

*Fiche Codex : Chevalier d'Émeraude originaire du Désert, compagnon fiable et père de famille qui évolue de guerrier fougueux à stratège expérimenté.*

## Ce que le texte dit de son apparence

*Phrases relevées automatiquement dans les romans, la plus probante en tête. À peser :
l'extraction attribue parfois à un personnage ce que la phrase dit de son voisin.*

> « Bergeau ressemblait aux hommes de son village avec ses cheveux bruns et ses yeux dorés, mais il était plus grand et plus musclé. »
>
> « Au cours du repas donné en son honneur ce soir-là, Bergeau avait remarqué les yeux bleus de la paysanne, aussi sombres que l’océan, et ses dents blanches qui étincelaient lorsqu’elle riait aux éclats. »
>
> « Bergeau lut alors dans ses yeux l’amour, la passion, le désir qu’elle ne pouvait pas dire devant tous ces témoins. »
>
> « Le premier dragon s’enfonça dans le sol juste devant Bergeau qui eut à peine le temps de voir sa tête hideuse et ses yeux rougeoyants. »

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

`jeu/art/personnages/bergeau.png` — fond transparent, PNG sans compression avec perte.
