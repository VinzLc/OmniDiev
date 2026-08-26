# Le jeu

```bash
npm run jeu              # jouer
npm run jeu -- --editeur # ouvrir l'éditeur Godot
```

Flèches pour marcher. **Espace** devant le brasier pour parler, Espace encore pour fermer.

## Ce qui s'y trouve

Une salle du Château d'Émeraude : une allée de tapis, une estrade, du dallage autour,
des murs qui arrêtent, un brasier qui parle. C'est l'étape 0 — le socle sur lequel tout
le reste viendra.

## Pourquoi il n'y a presque pas de `.tscn`

La scène est bâtie dans [`main.gd`](main.gd), pas décrite dans un fichier d'éditeur. Un
`.tscn` écrit à la main dépend d'identifiants de ressources que l'éditeur génère ; le code,
lui, se relit et se corrige. Le `.tscn` restant ne fait qu'accrocher le script.

## D'où viennent les images

De `jeu/art/`, produites par l'atelier graphique, et **copiées** dans `assets/` par
`npm run jeu`. On copie plutôt que de partager : un projet Godot importe tout ce qu'il
trouve sous sa racine, et l'ouvrir sur `jeu/art/` lui ferait avaler les centaines d'images
brutes de `sources/`.

Leur disposition n'est pas une convention interne mais celle qu'écrit `art:normalise` :

| | |
|---|---|
| `wellan.png` | 4 colonnes × 4 rangées de 32×32 — face, dos, profil gauche, profil droit |
| `chateau-d-emeraude.png` | 16 tuiles de 16×16, rangées par signature de coins |

Le sol emploie ces seize tuiles en jeu de Wang : chaque case se choisit par ses quatre
coins, `colonne = NO*8 + NE*4 + SO*2 + SE`. C'est ce qui permet au tapis d'avoir n'importe
quelle forme sans qu'on dessine un seul cas particulier.

## Vérifier sans jouer

```bash
godot --path jeu/godot --capture --quit-after 900
```

Le mode `--capture` joue une courte partie tout seul — monter l'allée, buter contre le mur,
redescendre au brasier, ouvrir le dialogue — et enregistre une image à chaque étape. Il
passe par `Input.parse_input_event`, donc par le chemin exact d'un joueur, touches
comprises : une vérification qui contourne le chemin normal ne prouve rien de ce chemin.

Il imprime aussi ce qu'il mesure — distance parcourue, position d'arrêt contre le mur,
entrée en zone, ouverture du dialogue.
