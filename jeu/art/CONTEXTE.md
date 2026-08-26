# Contexte à poser avant toute commande

À donner **une fois** à l'IA graphique, en ouverture de session. Chaque commande de
`jeu/art/commandes/` vient ensuite s'y appuyer sans le répéter.

---

## Le projet

Tu produis les graphismes d'un jeu de rôle en pixel art, adapté des **Chevaliers
d'Émeraude** d'Anne Robillard — une épopée de fantasy médiévale se déroulant sur le
continent d'Enkidiev. On y incarne Wellan, chef de l'Ordre des Chevaliers.

La référence visuelle est précise : **les Pokémon de la Game Boy Advance**, Rubis, Saphir
et Émeraude (2002-2005). Vue de dessus en trois quarts, personnages trapus, décors lisibles
à petite échelle.

## La contrainte matérielle, qu'on respecte volontairement

La Game Boy Advance affichait 15 bits de couleur et travaillait par palettes de 16 teintes.
On s'y tient, parce que c'est cette contrainte qui donne au style son identité :

- **aplats francs**, jamais de dégradé ;
- **ombrage à deux tons** : une couleur de base, une ombre. Pas de troisième nuance ;
- **aucun anti-aliasing** — chaque pixel est net, aucun pixel intermédiaire ;
- **contour sombre** régulier autour des personnages et des objets ;
- lisibilité d'abord : un trait qui disparaît à 32 pixels ne sert à rien.

## La palette du monde

Toutes les images puisent dans ces teintes. Un asset donné n'en utilise que **16 au plus**,
mais toujours prises ici — c'est ce qui fait tenir ensemble des images produites
séparément.

### Pierre et neutres — les châteaux, les murailles, le cristal

`#0B0A10` `#22222C` `#454652` `#71727E` `#A6A8B2` `#DDDDE4` `#F2F2F5`

Le noir domine les romans (2 080 occurrences) : c'est la couleur de base des Chevaliers.
Le cristal (1 128) et l'argent (1 105) donnent les hautes lumières.

Ces gris gardent une pointe de froid, pas davantage. La première version penchait
nettement vers le mauve — `#736C82` porte 22 points de bleu de plus que de vert. Sur un
sprite, la nuance passe ; sur un sol entier, la salle vire au lavande. Un neutre employé en
grande surface doit être neutre pour de bon.

### Verts de l'Ordre — surcots, bannières, végétation

`#0F3826` `#1C7A4E` `#43C47F` `#8FE0AC`

### Ors, cuirs et bois — la croix de l'Ordre, les torches, le mobilier

`#3D2A12` `#7A5223` `#C08F34` `#F0D174`

### Carnations

`#6B4230` `#A9714E` `#D9A57C` `#F2D3B0`

### Accents narratifs — à n'employer que là où le récit les appelle

`#5C3570` `#A76BC4` — le mauve de Kira, sa signature dans toute la saga
`#2D5FA8` `#5B9BD8` — le bleu perçant des yeux de Wellan, l'eau
`#8B2020` `#D14545` — le sang, le feu, l'Empereur Noir
`#5E9AA8` `#A8D6E0` `#E3F3FE` — les froids du nord : la neige de Shola, la glace, le cristal

Les trois derniers ont été ajoutés après coup. La palette était née des mots de couleur du
premier tome, où l'on parle surtout de noir, de vert et d'or ; elle ignorait le froid. Faute
d'équivalent, les bleus d'un plateau enneigé se rangeaient sur le vert de l'Ordre, et Shola
sortait mouchetée de vert.

## L'uniforme des Chevaliers, tel que le texte le décrit

> « Habillés tout en noir, ils portaient par-dessus leurs vêtements un **surcot deux tons**
> avec la croix d'Émeraude en noir sur le côté vert et un dragon vert sur le côté noir. »

> « Les émeraudes enchâssées dans la **croix dorée** de l'Ordre sur leur cuirasse brillaient
> sous les premiers rayons du soleil. »

Donc : base noire, surcot mi-vert mi-noir, croix dorée sertie d'émeraudes, bottes de cuir
noir. C'est l'élément qui doit être reconnaissable d'un personnage à l'autre.

## Les formats, invariables

| Ce qu'on demande | Dimensions | Disposition |
|---|---|---|
| Sprite de personnage | 32×32 px par image | planche 128×128 — 4 colonnes × 4 rangées |
| Jeu de tuiles | 16×16 px par tuile | planche de 16 colonnes |
| Portrait de dialogue | 96×96 px | image seule |

Les quatre rangées d'une planche de personnage, dans cet ordre : **face, dos, profil
gauche, profil droit**. Les quatre colonnes : **repos, pas gauche, repos, pas droit**.

**Fond strictement transparent** pour les personnages et les tuiles ajourées. PNG, sans
compression avec perte.

## Ce qu'il ne faut jamais produire

- du rendu 3D, de la peinture numérique, du style anime moderne ;
- de l'anti-aliasing, des dégradés, du flou, des ombres portées douces ;
- du texte, un filigrane, un cadre, une signature ;
- un décor derrière un sprite : le fond reste transparent ;
- une image aux dimensions approchantes — 32×32 signifie 32×32.

## Le protocole de cohérence

C'est le point le plus fragile de tout l'exercice. Deux images du même personnage produites
séparément ne se ressemblent presque jamais.

1. **Un personnage à la fois.** Produire d'abord la rangée « face » seule. La valider.
2. **Puis s'en servir de référence** pour les trois autres rangées, en la fournissant à
   chaque fois — plutôt que de demander les seize images d'un coup.
3. **Pour les tuiles**, vérifier le raccord avant tout le reste : une tuile qui ne se répète
   pas proprement, en horizontal comme en vertical, est inutilisable quelle que soit sa
   beauté.
4. **En cas de doute sur une teinte**, reprendre celle de la palette ci-dessus plutôt que
   d'en approcher une nouvelle.

## Comment les commandes arrivent

Chaque commande donne le rôle du personnage ou du lieu, puis **des phrases tirées
directement des romans** qui en décrivent l'apparence. Ces phrases font autorité sur toute
autre considération esthétique : si le texte dit « les cheveux blond foncé frôlant ses
épaules », le sprite a les cheveux blond foncé sur les épaules.

Elles sont relevées automatiquement, et il arrive qu'une phrase décrive le voisin plutôt
que le sujet. Elle est alors à écarter — les commandes le signalent.
