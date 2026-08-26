# Le jeu

```bash
npm run jeu              # jouer
npm run jeu -- --editeur # ouvrir l'éditeur Godot
```

| | |
|---|---|
| Flèches | marcher |
| Espace | parler, tourner la page, reprendre après une chute |
| J | l'épée |
| K | le feu de Theandras |

Les deux jauges, en haut à droite : la vie en rouge, l'énergie en bleu. L'énergie se refait
seule ; la vie, non.

## Ce qui s'y trouve

**Le chapitre I,1 des Chevaliers d'Émeraude, jouable.** Wellan se présente au Roi
fondateur, rallie ses six compagnons, apprend l'incident des pèlerins de Shola, puis reçoit
la Reine Fan qui lui confie sa fille avant de disparaître.

## Ce que le texte impose au combat

La fiche des hommes-insectes dit une carapace « les rendant invulnérables à la magie ». Le
sort glisse donc sur eux, et il faut le fer. Les dragons, que le chapitre 26 fait tomber
dans les fosses et enflammer, brûlent très bien.

Ce n'est pas de l'équilibrage : ce sont deux registres de combat que l'œuvre impose, et que
le joueur doit reconnaître pour s'en sortir.

## Comment une scène est écrite

Un fichier de `donnees/scenes/`. Chaque étape attend qu'on ait parlé à quelqu'un — ou à tout
un groupe, auquel cas l'objectif décompte ce qui reste. Elle peut faire entrer et sortir des
personnages : c'est ainsi que la Reine arrive et s'en va.

```json
{
  "id": "les-six",
  "objectif": "Parler à tes six compagnons",
  "attend": { "parler_tous": ["santo", "bergeau", "jasson", "dempsey", "falcon", "chloe"] },
  "dialogues": { "falcon": [ { "qui": "falcon", "dit": "…" } ] }
}
```

`qui` vaut un identifiant de fiche, ou `recit` pour ce que le joueur voit sans qu'on le lui
dise. Un personnage auquel la scène n'a rien écrit n'est pas muet pour autant : il retombe
sur sa fiche du Codex.

**Les répliques sont écrites pour le jeu**, d'après les résumés de chapitre et les fiches.
Aucune phrase des romans n'y figure — le dépôt est public, et les romans n'en sortent pas.

## L'étape 0, pour mémoire

Une salle du Château : une allée de tapis, une estrade, du dallage autour, des murs qui
arrêtent. C'est le socle sur lequel le reste est venu.

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

Le mode `--capture` joue **le chapitre en entier** tout seul — le Roi, les six compagnons,
Armène, la Reine — et enregistre une image au milieu de chaque échange. Au milieu, non à la
fin : prise à la fin, elle ne montrait que la salle vide, et l'on vérifiait que le dialogue
se ferme au lieu de vérifier qu'il s'affiche. Il
passe par `Input.parse_input_event`, donc par le chemin exact d'un joueur, touches
comprises : une vérification qui contourne le chemin normal ne prouve rien de ce chemin.

Il imprime aussi ce qu'il mesure — distance parcourue, position d'arrêt contre le mur,
entrée en zone, ouverture du dialogue.
