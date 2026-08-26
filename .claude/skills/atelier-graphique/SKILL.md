---
name: atelier-graphique
description: Produire, normaliser et contrôler les images du jeu OmniDiev — sprites de personnages, jeux de tuiles, portraits. À employer dès qu'il s'agit de commander une image à PixelLab, d'intégrer un rendu dans jeu/art/, ou de comprendre pourquoi une planche ne passe pas le contrôleur.
---

# Atelier graphique

Le circuit : **le texte commande, l'IA dessine, Godot consomme.**

```
commandes/<id>.md   npm run art            rédigée depuis le Codex et les romans
      ↓             npm run art:generer    jouée via l'API PixelLab
sources/<id>/                              le rendu brut, tel qu'il tombe
      ↓             npm run art:normalise  palette alignée, planche assemblée
personnages/<id>.png                       ce que Godot lit
      ↓             npm run art:verifier   contrôle mécanique
```

## La règle qui prime sur toutes les autres

**Le contrôleur ne voit pas ce qui compte.** Il mesure la géométrie, la taille de palette,
la transparence. Il ne sait pas qu'un visage est vert.

Cela s'est produit. `npm run art:verifier` a dit « conforme » sur une planche où Wellan
avait le visage vert et où son manteau vert-olive était devenu noir. Trois itérations
perdues, rattrapées uniquement en regardant l'image.

Donc, après **toute** normalisation :

```bash
node -e 'require("sharp")("jeu/art/personnages/<id>.png").resize(640,640,{kernel:"nearest"}).png().toFile("/tmp/sheet.png").then(()=>0)'
```

puis lire `/tmp/sheet.png`. Comparer au rendu brut de `sources/` quand un doute subsiste.
Ne jamais committer une planche qu'on n'a pas regardée.

## Dépenser chez PixelLab

```bash
npm run art:generer -- --solde
npm run art:generer -- --perso Wellan --action walking --frames 4          # une direction
npm run art:generer -- --perso Wellan --action walking --directions south,north,east,west
```

**Ce que ça coûte, mesuré :** un jeu de tuiles **0,007 USD**, un personnage **0,011 USD**.
Dessiner les 363 silhouettes restantes reviendrait à quatre dollars. L'art n'est plus la
contrainte — le temps d'écriture l'est. Continuer néanmoins à annoncer la dépense : bon
marché n'est pas gratuit, et le mode `pro` reste vingt à quarante fois plus cher.

**Sonder une direction avant d'engager les quatre.** Mesuré : un cycle de quatre images
coûte **une génération par direction**. Mais le mode `pro` en consomme **vingt à quarante
par direction** — s'y aventurer par accident vide un budget en un appel.

Animer part du `character_id` déjà validé (`GET /characters`), jamais d'une nouvelle
description : c'est ce qui garantit que le personnage animé soit le même que celui qu'on a
accepté.

Deux paramètres puissants et encore inexploités : `force_colors` avec une `color_image` sur
la création de personnage, et `color_palette` sur `create-tileset`. Ils imposent la palette
**à la génération** — ce qui supprime le problème au lieu de le corriger après coup.

## Les portraits

```bash
npm run art:generer -- --portrait wellan --taille 128
npm run art:generer -- --portrait elund --taille 128 --graine 91177
```

`portrait-character-pro` en `character_to_portrait` remonte **du sprite vers le visage** : le
portrait ressemble au personnage déjà validé, ce qu'aucune description ne garantirait. Jusqu'à
160 px — un portrait n'entre pas dans la grille du monde, il occupe un coin de la boîte de
dialogue.

**Il coûte 0,126 USD, douze fois un sprite.** Sonder sur un seul avant d'en commander treize.

**Il lit la planche, pas le rendu brut** — sans quoi il ignore les retouches. Le portrait de
Wellan est sorti auburn parce que je lui donnais `sources/`, alors que sa planche porte le
blond depuis longtemps.

**Et pour un visage qu'on veut décrire, ce n'est pas le bon endpoint.**
`portrait-character-pro` n'accepte aucun texte : on ne peut lui demander ni une carrure, ni
une longueur de cheveux, ni un âge. Il a rendu Wellan tour à tour auburn, puis lion — il
avait lu une crinière dans des mèches que j'avais éclaircies — puis adolescent imberbe.

```bash
npm run art:generer -- --visage wellan --taille 128 --amorce 0 --graine 6607
```

`create-image-pixflux` prend une description, et coûte moins d'un millième de dollar. **Mettre
l'amorce à zéro** : à 300 sur 1000, le sprite dominait encore et l'on récupérait le sprite
lui-même. Compter cinq à huit graines pour un visage juste, ce qui reste moins cher qu'un
seul portrait déduit.

L'endpoint ne prend aucun texte : le seul levier de reprise est la graine. Élund est sorti
rajeuni de quarante ans à deux essais sur trois — un sprite de 36 pixels ne porte pas assez
d'information pour qu'un vieillard s'y lise. Et **juger sur la vignette trompe** : ce que
j'avais pris pour des lunettes de soleil sur Falcon était l'ombre de sa capuche, si bien que
j'ai dégradé un bon portrait en le regénérant.

## Ne pas régénérer un personnage déjà validé

Le rendu s'écarte parfois du texte — Wellan avait les cheveux auburn là où les romans disent
« blond foncé ». Le réflexe est de régénérer avec une consigne corrigée. **Deux tentatives,
deux échecs**, une génération chacune.

L'endpoint `create-character-with-4-directions` ne produit pas le style du gabarit
`mannequin` employé par l'interface web : le géant est revenu frêle, sans armure, sans cape
ni croix dorée. La couleur des cheveux était corrigée, tout le reste perdu.

La première tentative a en plus changé trois variables d'un coup — formulation,
`force_colors`, `flat shading` — si bien qu'on ne savait plus laquelle avait nui. **Changer
une chose à la fois**, surtout quand chaque essai coûte.

**Préférer la retouche.** `jeu/art/sources/<id>.retouche.json` déclare un décalage de teinte
que `art:normalise` applique à toutes les images d'un coup. Viser demande la couleur *et* la
position : les mèches partagent leurs bruns avec les cuirs du corps, et la tête porte aussi
la peau et les yeux. Conserver la luminance — c'est elle qui porte le modelé.

## Un uniforme partagé ne supporte aucun vêtement dans le bloc personnel

Les sept Chevaliers portent le même surcot. Le bloc d'uniforme est donc écrit une fois et
inséré **au caractère près** dans les sept commandes — un script les compose, sinon les
textes dérivent et l'Ordre se disloque.

Mais il suffit qu'une consigne personnelle mentionne un vêtement pour que tout se défasse.
Jasson, à qui l'on décrivait « une tunique verte sous la cuirasse », est sorti en armure
blanche ; Dempsey, porteur d'« une corde de cuir et un petit cor à la ceinture », en plastron
crème. Deux fois, la mention a supplanté l'uniforme au lieu de s'y ajouter.

Ajouter « rien de blanc ni d'argenté » n'y a rien changé : **une consigne négative ne corrige
pas une consigne positive concurrente**, elle s'y empile. Ce qui a marché est de vider le
bloc personnel de tout vêtement et de tout équipement, et de n'y laisser que le visage, les
cheveux et le port. Bergeau, dont la consigne n'en mentionnait aucun, était juste du premier
coup.

## Étendre la palette plutôt qu'écraser l'image

La palette du monde est née des mots de couleur du premier tome — noir, vert, or. Elle
ignorait le froid. Le premier jet de Shola est donc sorti **moucheté de vert** : faute
d'équivalent, les bleus d'un plateau enneigé se rangeaient sur le vert de l'Ordre.

La correction n'a pas demandé de regénérer. Trois teintes ajoutées à `CONTEXTE.md`, une
normalisation, et la neige est devenue de la neige. **Quand une région apporte des couleurs
que le monde ne connaît pas, c'est le monde qui s'étend.**

## Les pièges déjà payés

**La palette de `CONTEXTE.md` est une consigne de génération, pas une cible de
quantification.** Y ramener toutes les couleurs de force écrase le modelé : la vue de dos de
Wellan, dont les valeurs vivent entières sous L=114, n'y trouvait que six marches.

**Ne jamais ranger un neutre.** Sous une chroma de 0,05, une couleur n'a pas d'identité à
unifier — et la ranger retourne sa teinte. Le vert olive du manteau (chroma 0,011) trouvait
à 0,038 un gris violacé : assez près pour passer tout seuil de distance, assez loin pour
noircir le manteau. Le ramenage ne porte que sur ce qui porte une identité : le vert de
l'Ordre, l'or de la croix, le mauve de Kira.

**Fusionner les quasi-jumelles.** Deux états d'un même personnage ne rendent pas exactement
les mêmes noirs — `#222621` au repos, `#222620` en marche. Laissés distincts, ces jumeaux
ont occupé onze des seize places ; il ne restait rien pour les carnations, qui se sont
repliées sur un vert.

**Choisir les seize teintes sur la part par image, jamais sur le total.** Sinon les frames
claires votent contre les sombres et leur prennent leurs marches.

**La direction d'une image d'animation est dans le chemin, pas dans le nom.** Un fichier
s'appelle `frame_000.png` sous `animations/walking/south/`. Chercher la direction dans le
nom seul rendrait la moitié du rendu invisible.

**L'API rend 44×44 pour un sprite de 32.** Recadrer en calant sur la **ligne de sol**, jamais
sur le centre géométrique, qui décale le personnage.

**La dernière image d'un cycle revient sur la première.** L'écarter avant d'échantillonner,
sinon le mouvement bat deux fois au même endroit.

## Les jeux de tuiles

```bash
npm run art:generer -- --tuiles chateau-d-emeraude   # lit commandes/<id>.tuiles.json
npm run art:normalise -- chateau-d-emeraude-tuiles   # → lieux/<id>.png + <id>.json
```

`create-tileset` ne produit **ni murs ni meubles** : c'est un tileset de Wang entre deux
sols, seize tuiles couvrant toutes les combinaisons de coins. C'est exactement la partie
qu'on ne réussit pas à la main, et celle dont dépend qu'un décor ne montre pas ses coutures.

La planche livrée range les tuiles par signature de coins — `colonne = NO*8 + NE*4 + SO*2 + SE`
— pour que le moteur trouve la bonne par calcul.

**Quatre pièges, tous payés d'une génération chacun.**

*Les métadonnées de coins mentent.* Un rendu a désigné par « upper » l'inverse de ce que
montraient les images ; un autre a déclaré uniforme une tuile qui portait une bordure. La
signature se **déduit des pixels**, jamais des étiquettes — et en ignorant le liseré de
transition, qui n'est ni l'un ni l'autre terrain et faisait basculer les quadrants qu'il
traversait.

*Le liseré appartient à la transition, jamais au terrain.* Écrit dans `upper_description`,
il s'est retrouvé peint dans le tapis lui-même — 37 pixels dorés sur 256 dans la tuile
censée être unie, et des rayures d'or en travers de toute la salle.

*Trop contraindre fait dégénérer.* « NO pattern, low detail » a rendu les seize tuiles si
semblables qu'il n'en restait que six signatures distinctes. Le raccord a besoin de matière
pour s'apprendre.

*La palette envoyée en `color_image` gouverne la sortie.* Les neutres du monde penchaient
vers le mauve ; la salle entière est sortie lavande. Sur un sprite la nuance passe, sur un
sol elle saute aux yeux. Corrigé dans `CONTEXTE.md`.

**Le test qui compte n'est pas de regarder les tuiles alignées** mais d'en assembler une
salle et d'y chercher les coutures. Toutes les fautes ci-dessus étaient invisibles sur la
bande des seize.

## Les formats, invariables

| | Dimensions | Disposition |
|---|---|---|
| Sprite | 32×32 par image | planche 128×128, 4 colonnes × 4 rangées |
| Tuiles | 16×16 | planche de 16 colonnes |
| Portrait | 96×96 | image seule |

Rangées, dans l'ordre : **face, dos, profil gauche, profil droit**. Colonnes : les quatre
images du cycle. Fond strictement transparent, PNG sans perte.

## Ce que le texte impose

Les phrases des romans font autorité sur toute considération esthétique. `lib/appearance.ts`
les extrait, et se trompe parfois de sujet — une phrase peut décrire le voisin. Les écarter
plutôt que de les suivre.

Écart connu et non corrigé : Wellan a les cheveux auburn dans le rendu, « blond foncé » dans
le texte.

**Ce que le texte donne pour distinguer sept hommes en même uniforme**, et qui vaut mieux
que n'importe quelle invention : Bergeau a « les cheveux bruns et les yeux dorés », plus
grand et plus musclé ; Falcon promène « son regard turquoise » ; Chloé est « mince mais
vigoureuse, cheveux blonds assez courts, yeux d'un bleu très clair ». Santo joue de la harpe,
Dempsey est prince de Béryl et pisteur, Jasson est le rieur. `lib/appearance.ts` sort les
trois premières ; les fiches du Codex donnent les trois autres.

Wellan reste plus large que tous — 24 pixels contre 14. Ce n'est pas une dérive de style
mais l'écart entre l'interface web et l'API : il tombe juste, puisque le texte en fait « un
géant parmi ses frères d'armes ».
