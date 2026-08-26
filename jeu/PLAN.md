# Chantier Enkidiev

Un RPG dans l'esprit des Pokémon Game Boy Advance, où l'on incarne Wellan à travers les
quatre épopées d'Anne Robillard.

Version consultable : https://claude.ai/code/artifact/9aed92a7-e5e7-449f-a307-464603db08ba

---

## Ce qu'on a déjà

L'Oracle a produit la bible de contenu qu'un projet de cette ampleur met des mois à
rassembler. **Le découpage narratif est déjà fait.**

| | |
|---|---|
| 365 | personnages décrits, avec leur évolution et leurs liens |
| 57 | lieux — la matière première des cartes |
| 1 441 | résumés de chapitre, autant de scènes candidates |
| 196 | personnes reliées par la généalogie |
| 3 339 | relations exploitables en dialogues et en quêtes |
| 19 842 | fragments citables pour écrire au plus près du texte |

**Wellan paraît dans 43 des 44 volumes**, sur les quatre épopées. Le fil du protagoniste
n'est pas un choix arbitraire : c'est celui que l'œuvre impose.

## Le goulot s'est déplacé

Le style GBA exige tilesets, sprites de marche en quatre directions et portraits. Claude ne
sait pas dessiner de pixel art — mais une IA générative spécialisée, si. Le rôle de Claude
devient donc d'**écrire les commandes** ; celui de l'humain, de les jouer et de rapporter
les images.

Ce qui change tout : **les romans décrivent les personnages.** Wellan, ce n'est pas une
invention — c'est *« les cheveux blond foncé frôlant ses épaules, les yeux d'un bleu
perçant, un géant parmi ses frères d'armes »*.

```bash
npm run art -- --lot etape0
```

Le script joint, pour chaque entité : la fiche du Codex (le rôle), **les phrases des romans
qui décrivent l'apparence**, la spécification technique, et le chemin du fichier attendu.

La difficulté restante n'est plus de produire, mais de **tenir la cohérence** — seize images
d'une planche doivent montrer la même personne, les tuiles doivent s'abouter. Voir
[jeu/art/README.md](art/README.md).

## L'échelle, sans euphémisme

*Pokémon Émeraude*, c'est ~380 cartes produites par un studio. Une épopée compte 600
chapitres ; même à une carte pour cinq chapitres, cela fait 120 cartes pour un quart de
l'œuvre. **C'est un projet de plusieurs années.**

D'où la méthode : **chaque étape doit être jouable, pas seulement livrée.**

---

## Les étapes

### 0 — Le squelette qui marche ✓

Wellan se déplace dans une salle du Château d'Émeraude, se cogne aux murs, parle à un
personnage. Rien d'autre.

> **Terminé quand** `git pull` puis `npm run jeu` ouvre une fenêtre où l'on marche et où une
> boîte de dialogue s'affiche — sur une machine qui n'a jamais vu le projet.

Fait. Une salle du Château, un cycle de marche en quatre directions, des murs qui arrêtent,
une boîte de dialogue. Le mode `--capture` rejoue la scène tout seul et enregistre ce qu'il
voit, en passant par le chemin d'entrée d'un vrai joueur.

### 1 — La passerelle Codex → jeu ✓

Un script transforme les fiches en données de jeu : personnages, lieux, répliques. C'est ce
qui rend l'échelle tenable.

> **Terminé quand** ajouter un personnage ne demande que son identifiant de fiche.

Fait. `npm run jeu:donnees` verse les 365 personnages et 57 lieux du Codex dans
`monde.json` — noms, rôles, tomes de présence, liens. Une salle est un fichier de données ;
un personnage y tient en un identifiant de fiche et trois nombres, et ses répliques se
déduisent de sa fiche. Sans planche, il paraît en silhouette teintée : le contenu n'attend
pas l'art.

Une limite posée d'emblée : **les répliques viennent des fiches, jamais des romans.**
`monde.json` est versionné pour qu'un `git pull` suffise, or `data/` ne l'est pas — y verser
de la prose d'Anne Robillard la republierait.

### 2 — Une vraie scène du roman ✓

Le chapitre I,1 rejouable : la fondation de l'Ordre, les sept enfants, le Roi Émeraude Ier.

> **Terminé quand** quelqu'un qui connaît la saga reconnaît la scène, et quelqu'un qui ne la
> connaît pas la comprend.

Fait. Quatre temps jouables : se présenter au Roi, rallier les six compagnons, apprendre
l'incident des pèlerins, recevoir la Reine Fan. Douze personnages, quarante-quatre
répliques, un objectif qui suit le chapitre et décompte ce qui reste.

Les répliques sont **écrites**, d'après le résumé du chapitre et les fiches — jamais
prélevées dans les romans. C'est la contrainte posée à l'étape 1, et elle tiendra pour les
1 440 chapitres suivants.

### 3 — Les systèmes RPG ◐

Combat, magie, inventaire, progression. L'étape la plus longue des cinq.

> **Terminé quand** on peut perdre.

**Le critère est atteint** : Wellan tombe, et l'on reprend la ligne. Le chapitre I,26 — la
nuit où la première vague débarque à Zénor — est jouable, avec deux jauges, l'épée, le feu
de Theandras, et des vagues qui se relèvent.

La mécanique vient du texte, non de l'équilibrage. La fiche des hommes-insectes dit une
carapace « les rendant invulnérables à la magie » : le sort glisse sur eux et il faut le
fer. Les dragons, eux, brûlent — le chapitre les fait tomber dans les fosses et les
enflammer. Deux registres, imposés par l'œuvre.

**Ce qui manque encore à l'étape** : l'inventaire et la progression. Ni l'un ni l'autre
n'est requis par le critère, mais ni l'un ni l'autre n'existe.

### 4 — La direction artistique ◐

La production d'images tourne en parallèle dès l'étape 0. Cette étape est celle du regard
d'ensemble : harmoniser les palettes, reprendre ce qui jure, fixer une charte.

> **Terminé quand** une capture d'écran donne envie d'y jouer.

La nuit de Zénor y répond : le dallage antique prend la lueur de Wellan, les cavaliers
insectes sortent du noir la lance haute, un dragon fond sur la grève. Quatre planches
existent — Wellan, Émeraude Ier, l'homme-insecte, le dragon — et l'échelle des figures est
fixée dans [la charte](art/CHARTE.md).

**Ce qui manque** : 363 personnages sont encore des silhouettes teintées. C'est le
dispositif, non un oubli — mais l'étape ne sera close que quand les visages du chapitre I,1
existeront.

### 5 — La mise à l'échelle ← en cours

Outillage d'édition de cartes, chapitres en série.

> **Terminé quand** un chapitre supplémentaire coûte des heures, pas des semaines.

L'épine dorsale existe : `campagne.json` donne l'ordre de lecture, un chapitre achevé appelle
le suivant, et la partie se retrouve où on l'a laissée. **Ajouter un chapitre, c'est écrire
son fichier de scène et glisser son identifiant dans la liste** — plus les personnages qu'il
exige, une génération chacun.

Sept chapitres s'enchaînent : **I,1 · I,2 · I,3 · I,4 · I,6 · I,7 · I,26** — de la fondation
de l'Ordre au massacre de Shola et à la révélation sur Kira, puis au premier débarquement de
Zénor.

Le coût d'un chapitre est désormais connu : son écriture, plus les décors et personnages
qu'il exige — **0,007 USD le jeu de tuiles, 0,011 le personnage**. L'art n'est plus la
contrainte ; le temps d'écriture l'est.

Tous les chapitres ne sont pas jouables tels quels. Le roman coupe d'un lieu à l'autre ; un
jeu qui suit Wellan ne le peut pas. Le chapitre I,5 se déroule au château pendant qu'il est
sur la route : sa scène est repliée sur son sommeil, ce que les pouvoirs télépathiques de
Kira autorisent. Le champ `avertissement` de chaque scène dit ce qui a été replié.

---

## Décisions prises

| Sujet | Choix | Pourquoi |
|---|---|---|
| Moteur | **Godot 4.6** | Déjà installé, et vérifié : s'exécute en ligne de commande et lance du GDScript. |
| Dépôt | **Même dépôt, `jeu/`** | Accès direct au Codex, un seul `git pull`, aucune donnée dupliquée. |
| Graphismes | **Génération pilotée par le texte** | `npm run art` écrit les commandes depuis les romans ; les images reviennent dans `jeu/art/`. |
| Orchestration | **Pas de `squad`** | Orchestrateur pour GitHub Copilot. Il résout le débit de code, qui n'est pas notre goulot. |
| Combat | **Action en temps réel** | Tranché à l'étape 3. Épée au contact, sort à distance, adversaires qui marchent sur vous. |

## Ce qui reste ouvert

- **Le droit d'auteur.** Jeu de fan tiré d'une œuvre protégée, sur un dépôt public. Le code
  et les résumés générés sont d'une autre nature que les romans — qui ne quittent pas la
  machine — mais la question mérite d'être posée avant que le projet gagne en visibilité.
- **La langue.** Français seul, ou structure prête pour l'anglais ? Prévoir les deux dès
  l'étape 1 ne coûte presque rien ; rétro-adapter coûte cher.
