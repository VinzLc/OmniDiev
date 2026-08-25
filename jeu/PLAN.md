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

## Le goulot n'est pas le code

Le style GBA exige tilesets, sprites de marche en quatre directions, portraits de dialogue
et interface. Claude ne sait pas dessiner de pixel art, et les spritesheets générées n'ont
pas la cohérence qu'un jeu demande. **C'est ce qui plafonnera le projet.**

Trois voies : pack sous licence libre (rapide, générique), artiste (le bon résultat, du
budget), ou toi. On démarre en placeholder pour ne pas bloquer la preuve que la chaîne
fonctionne ; la direction artistique se décide à l'étape 4.

## L'échelle, sans euphémisme

*Pokémon Émeraude*, c'est ~380 cartes produites par un studio. Une épopée compte 600
chapitres ; même à une carte pour cinq chapitres, cela fait 120 cartes pour un quart de
l'œuvre. **C'est un projet de plusieurs années.**

D'où la méthode : **chaque étape doit être jouable, pas seulement livrée.**

---

## Les étapes

### 0 — Le squelette qui marche ← prochaine

Wellan se déplace dans une salle du Château d'Émeraude, se cogne aux murs, parle à un
personnage. Rien d'autre.

> **Terminé quand** `git pull` puis `npm run jeu` ouvre une fenêtre où l'on marche et où une
> boîte de dialogue s'affiche — sur une machine qui n'a jamais vu le projet.

### 1 — La passerelle Codex → jeu

Un script transforme les fiches en données de jeu : personnages, lieux, répliques. C'est ce
qui rend l'échelle tenable.

> **Terminé quand** ajouter un personnage ne demande que son identifiant de fiche.

### 2 — Une vraie scène du roman

Le chapitre I,1 rejouable : la fondation de l'Ordre, les sept enfants, le Roi Émeraude Ier.

> **Terminé quand** quelqu'un qui connaît la saga reconnaît la scène, et quelqu'un qui ne la
> connaît pas la comprend.

### 3 — Les systèmes RPG

Combat, magie, inventaire, progression. L'étape la plus longue des cinq.

> **Terminé quand** on peut perdre.

### 4 — La direction artistique

Remplacer les placeholders, une fois les besoins réels connus. Le faire trop tôt, c'est le
refaire deux fois.

> **Terminé quand** une capture d'écran donne envie d'y jouer.

### 5 — La mise à l'échelle

Outillage d'édition de cartes, chapitres en série.

> **Terminé quand** un chapitre supplémentaire coûte des heures, pas des semaines.

---

## Décisions prises

| Sujet | Choix | Pourquoi |
|---|---|---|
| Moteur | **Godot 4.6** | Déjà installé, et vérifié : s'exécute en ligne de commande et lance du GDScript. |
| Dépôt | **Même dépôt, `jeu/`** | Accès direct au Codex, un seul `git pull`, aucune donnée dupliquée. |
| Graphismes | **Pack libre en placeholder** | Jouable tout de suite ; la direction artistique attend l'étape 4. |
| Orchestration | **Pas de `squad`** | Orchestrateur pour GitHub Copilot. Il résout le débit de code, qui n'est pas notre goulot. |

## Ce qui reste ouvert

- **Le droit d'auteur.** Jeu de fan tiré d'une œuvre protégée, sur un dépôt public. Le code
  et les résumés générés sont d'une autre nature que les romans — qui ne quittent pas la
  machine — mais la question mérite d'être posée avant que le projet gagne en visibilité.
- **Le combat.** Tour par tour à la Pokémon, ou action en temps réel ? À trancher à l'étape 3.
- **La langue.** Français seul, ou structure prête pour l'anglais ? Prévoir les deux dès
  l'étape 1 ne coûte presque rien ; rétro-adapter coûte cher.
