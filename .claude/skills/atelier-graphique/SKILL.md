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

## Une image peut être vide, et rien ne le dit

Trois visages sur onze sont sortis en **carré gris uni** : bon format, bon poids, fichier
présent. `build-jeu-donnees` déclarait donc le portrait disponible, et le jeu l'affichait.
Le contrôleur mesurait la palette, la définition, les bords — il ne demandait pas s'il y
avait quelque chose dessus.

`npm run art:verifier` refuse désormais une image d'une seule couleur, et **contrôle aussi
`portraits/`**, qui lui échappait. Le remède est la graine : la même commande relancée avec
une autre a rendu les trois du premier coup.

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

Animer part du `character_id` déjà validé, jamais d'une nouvelle description : c'est ce qui
garantit que le personnage animé soit le même que celui qu'on a accepté.

**Mais l'identifiant se lit dans le carnet local, non chez le service.** Les treize premiers
ont été créés dans l'interface web, où l'humain leur a donné leur nom ; ceux que `--creer`
fabrique par l'API n'en reçoivent pas — le service les enregistre tous sous le nom de leur
état, c'est-à-dire **« Idle »**. Chercher par le nom ne pouvait donc jamais les retrouver, et
l'erreur listait cinquante descriptions entières en guise de « noms connus ». La création écrit
l'identifiant dans `jeu/art/sources/<id>/metadata.json` : c'est la source sûre, elle est
locale, elle est datée du moment où l'on a accepté le rendu.

**La taille se mesure, elle ne se devine pas.** Commandé à 26, un personnage sort à 33 pixels
au repos et jusqu'à **39 en pleine marche** — la jambe tendue est plus haute que la pose de
référence, et c'est l'animation qui décide du recadrage. Les planches validées tiennent entre
**29 et 31 pixels** pour un adulte, 21 pour Kira. On commande donc autour de **20 pour un
adulte, 18 pour un enfant**, et l'on vérifie la boîte réelle après normalisation plutôt que de
faire confiance au chiffre demandé.

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

## Les humeurs d'un portrait

```bash
npm run art:expressions -- wellan     # décline les cinq humeurs
```

**Aucun endpoint n'y arrive.** Trois voies essayées, trois échecs. Une description
d'expression avec image d'amorce : à toutes les forces, de 150 à 850, les cinq humeurs
rendaient le même visage impassible. Sans amorce : cinq humeurs, cinq hommes différents. Un
repeint par `inpaint` avec masque : l'humeur arrivait, mais la barbe disparaissait et les
yeux perdaient leur bleu.

Ce qui marche est ce que le projet fait chaque fois qu'un modèle refuse d'obéir sur un
détail : **viser le détail soi-même**. Les sourcils et la bouche sont quelques dizaines de
pixels à des places qu'on mesure — les yeux bleus servent de repère, la bouche est la rangée
la plus sombre au-dessous. Le reste du portrait n'est jamais touché, donc c'est le même
homme **par construction**, non par chance. Coût nul, résultat exact.

## Trois pièges de commande, tous payés

**Seize pixels est le plancher du service.** Un enfant commandé à 15 revient en 422 dont le
corps parle de `image_size.width`. Le garde-fou est maintenant local : la commande refuse
avant l'appel, et rappelle les tailles usuelles.

**Une tunique de la couleur de la peau se lit comme une nudité.** Zach, huit ans, commandé en
« tunique sable » avec une carnation sable, est sorti nu deux fois de suite — le modèle
obéissait, mais sable et carnation sont la même famille et à trente-deux pixels rien ne les
sépare. La faute est dans la palette de la consigne, pas dans le rendu. Un vêtement doit
**contraster avec la peau**, et la consigne doit dire quelles parties du corps restent nues.

**Une couleur interdite se remplace par une autre couleur forte.** Cull, dont la consigne
n'énumérait que des gris, est sorti en robe rouge. Ce n'est pas de la désobéissance mais un
choix : le modèle veut une couleur saturée quelque part. Autant la choisir soi-même.

## La retouche de vêtement

`sources/<id>.retouche.json` accepte désormais un `vetement` en plus des `cheveux` : une
fenêtre de teinte, une teinte d'arrivée, un plafond de saturation. La luminance est conservée,
donc les plis survivent.

```json
{ "vetement": { "de": [332, 12], "teinte": 225, "saturationMax": 0.10, "pourquoi": "…" } }
```

C'est ce qui a ramené la robe de Cull du rouge — la couleur du sang, du feu et de l'Empereur
dans cette palette — vers le gris qu'un Roi d'**Argent** doit porter, sans remettre en jeu la
couronne et la fourrure obtenues au deuxième essai seulement.

**La carnation ne se reteint jamais, et la garde est dans le code.** Le premier essai visait
les rouges en `[340, 20]` : les ombres de la peau vivent à 20-30 degrés, et le roi est ressorti
le visage et les mains gris. C'est précisément ce que le contrôleur ne voit pas. Une fenêtre
mal bornée ne doit pas pouvoir produire un visage gris, donc le refus est dans `retoucher()` et
non dans le fichier qu'on écrit.

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
que `art:normalise` applique à toutes les images d'un coup.

**Mais la retouche ne vise que la chevelure** : bande des treize premières rangées, teintes
chaudes et sombres. Un vêtement sorti de travers — le surcot d'Écuyère de Bridgess est venu
turquoise là où l'Ordre est émeraude — n'a pas de remède bon marché. À trente-deux pixels
l'écart se lit comme un vert sombre, et l'étendre aux vêtements coûterait plus que le défaut. Viser demande la couleur *et* la
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

## Le mobilier

```bash
npm run art:generer -- --objet trone --taille 32
```

Lit `commandes/objet-<nom>.txt`, rend sur fond transparent dans `jeu/art/objets/`, et
`build-jeu-donnees` assemble la planche que le moteur découpe. **Trente-deux pixels et non
seize** : un trône ou une bannière montent plus haut qu'une tuile, et se posent calés par le
bas comme un personnage.

Les silhouettes dessinées au compas ont servi jusqu'à ce qu'on ait mieux — elles distinguaient
les sortes, elles ne les représentaient pas. Deux sortes ont demandé une reprise : une bannière
suspendue à rien s'est fait effacer par le détourage, et une table trop décrite est sortie en
bouillie grise. Les décrire **posées sur un support simple** et **remplissant le cadre** a
suffi.

**La banque compte vingt-six sortes**, mesurées à **0,006 USD pièce** — dix-sept d'un coup pour
0,110 USD, sans un seul rejet. La formule qui les rend toutes du même style tient en trois
temps, et il suffit de la suivre :

> *A single X, seen from a low top-down three-quarter angle, alone on nothing.* — puis une ou
> deux phrases de description, **courtes** — puis *Pixel art, Game Boy Advance style, flat
> fills, two-tone shading, hard black outline, no anti-aliasing. The object alone, centred,
> filling most of the frame, nothing around it.*

**Deux banques, deux usages.** `jeu/art/objets/` porte le mobilier qu'une salle pose,
`jeu/art/inventaire/` les icônes de ce qu'on ramasse — `npm run art:generer -- --item <nom>`,
commande dans `commandes/item-<nom>.txt`. Les mêler ferait apparaître une épée courte parmi les
meubles qu'on peut placer, et un brasero parmi ce qu'on range dans son sac.

**Une icône d'objet fin se couche en diagonale.** Debout, une épée de 32 pixels sort maigre et
lavande : la palette du monde n'a ni acier ni cuir, et un objet vertical n'occupe qu'une
colonne. « Lying at a diagonal across the frame, corner to corner, chunky and heavy, not
slender » — trois essais pour le trouver, puis huit réussites d'affilée. Neuf icônes pour
**0,092 USD**, reprises comprises.

**Aucune liste de sortes ne s'écrit plus.** `build-jeu-donnees` lit le dossier, range par ordre
alphabétique, assemble la planche et inscrit l'ordre dans `monde.json` ; le moteur l'y lit.
Ajouter un meuble, c'est déposer un PNG. Deux listes écrites à la main ne s'accordent pas
longtemps — c'est la faute qui avait lancé le jeu sans Kira ni la Reine.

**Une planche qui change de taille doit être réimportée.** `objets.png` est passée de huit
sprites à vingt-six ; Godot a continué de servir la texture de 256 pixels avec les nouveaux
indices, et les bannières de la salle du trône sont sorties en coffres. Aucune erreur, aucun
avertissement — l'image était simplement fausse. `npm run jeu` importe avant de lancer ; un
`godot --path` lancé à la main ne le fait pas, et c'est là qu'on se fait prendre.

**Ne pas régénérer sur la foi d'une vignette.** Sur la planche contact, le tabouret paraissait
n'avoir aucun pied et l'enclume paraissait bleue. Agrandis, les trois pieds étaient là et le
bleu était le marteau. Deux regénérations évitées, après en avoir déjà perdu une sur un
portrait jugé de la même façon.

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

**Deux terrains de même valeur ne se distinguent pas.** Un grès rouge sombre contre un tapis
cramoisi a rendu **neuf combinaisons de coins sur seize introuvables** : le détecteur lit les
pixels, et deux terrains de même clarté n'ont pas de frontière lisible. Le contraste de
clarté n'est pas un choix esthétique, c'est ce qui rend le raccord calculable. Grès **pâle**
contre tapis cramoisi est passé du premier coup.

**Un motif dessiné dans le terrain brouille aussi la signature.** « De grandes dalles polies
posées en grille régulière aux joints fins » : huit combinaisons manquantes. Le terrain se
décrit uni — « a flat expanse of pale jade green stone, smooth and even » — et la structure se
laisse au liseré de transition.

**Le nom du fichier est l'identifiant du lieu au Codex.** `build-jeu-donnees` cherche
`jeu/art/lieux/<id du lieu>.png` : une planche nommée `opale.png` laisse `royaume-d-opale`
avec `tuiles: null`, sans que rien ne le dise.

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
