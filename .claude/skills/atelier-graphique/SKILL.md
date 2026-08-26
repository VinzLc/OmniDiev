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

**Sonder une direction avant d'engager les quatre.** Mesuré : un cycle de quatre images
coûte **une génération par direction**. Mais le mode `pro` en consomme **vingt à quarante
par direction** — s'y aventurer par accident vide un budget en un appel.

Animer part du `character_id` déjà validé (`GET /characters`), jamais d'une nouvelle
description : c'est ce qui garantit que le personnage animé soit le même que celui qu'on a
accepté.

Deux paramètres puissants et encore inexploités : `force_colors` avec une `color_image` sur
la création de personnage, et `color_palette` sur `create-tileset`. Ils imposent la palette
**à la génération** — ce qui supprime le problème au lieu de le corriger après coup.

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
