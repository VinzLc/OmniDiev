# Château d'Émeraude — jeu de tuiles

*Fiche Codex : Forteresse royale du nord qui sert de siège aux Chevaliers d'Émeraude et de centre de formation pour les futurs défenseurs du royaume.*

## Ce que le texte dit du lieu

*Phrases relevées automatiquement dans les romans, la plus probante en tête.*

> « Le château se dressait sur une colline mais le pays tout entier semblait entouré d’une haute muraille de pierre. »
>
> « En temps normal, elle aurait dû voir les tours d’Émeraude, mais la trouée où le château s’élevait était vide ! »
>
> « Les deux femmes coururent jusqu’a l’une des ébauches de fenétres et constatérent que le chateau se trouvait maintenant au milieu de l’océan. »
>
> « N’ayant pas voulu courir le risque de se retrouver à des lieues du château en utilisant son vortex, Kira s’était précipitée 193 dans le grand escalier, suivie de Mahito et de Kaliska, afin de rejoindre son mari. »

## Ce qu'il faut produire

Un jeu de tuiles de **16×16 pixels**, sur une planche de 16 colonnes,
comprenant au minimum :

- sols : dalle, terre battue, herbe, tapis
- murs : face, angles intérieurs et extérieurs, base et sommet
- ouvertures : porte fermée, porte ouverte, fenêtre, escalier montant et descendant
- mobilier : table, banc, coffre, torche murale, bannière

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

## Raccord

**Chaque tuile de sol et de mur doit s'abouter à elle-même sans couture visible**, en
horizontal comme en vertical. Une tuile qui ne se répète pas proprement est inutilisable :
c'est la contrainte à vérifier avant tout le reste.

## Fichier attendu

`jeu/art/lieux/chateau-d-emeraude.png` — fond transparent pour les tuiles ajourées.
