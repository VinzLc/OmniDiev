---
name: jeu-godot
description: Travailler sur le jeu OmniDiev — le projet Godot de jeu/godot/, ses scènes de chapitre, son combat en temps réel, ses effets. À employer dès qu'il s'agit d'ajouter un chapitre, de toucher à main.gd, de vérifier que le jeu tourne, ou de comprendre pourquoi une animation ne joue pas.
---

# Le jeu

```bash
npm run jeu                    # reprendre la partie
npm run jeu -- --recommencer   # repartir du premier chapitre
npm run jeu -- --scene i-02    # un chapitre précis, sans toucher à la partie
```

Tout est bâti en GDScript dans [`main.gd`](../../../jeu/godot/main.gd) ; le `.tscn` n'accroche
que le script. Un fichier d'éditeur écrit à la main dépend d'identifiants de ressources
générés, le code se relit.

## Ajouter un chapitre

1. Écrire `donnees/scenes/<id>.json` — étapes, conditions, répliques.
2. Glisser l'identifiant dans `donnees/campagne.json`.
3. Générer les personnages manquants (voir **atelier-graphique**).

**Le bloc `fin` est une étape comme les autres, condition comprise.** Sans `attend`, le
chapitre reste ouvert et n'appelle jamais le suivant — c'est le premier piège.

Les répliques sont **écrites**, jamais prélevées dans les romans : le dépôt est public.

**Tous les chapitres ne sont pas jouables tels quels.** Le roman coupe d'un lieu à l'autre ;
un jeu qui suit un seul protagoniste ne le peut pas. Le chapitre I,5 se déroule au château
pendant que Wellan est sur la route : sa scène a été repliée sur le sommeil de Wellan, ce que
les pouvoirs télépathiques de Kira autorisent et que le chapitre I,8 confirme.

Replier ainsi ou sauter — mais le dire dans le champ `avertissement` de la scène, et
n'inventer aucun pouvoir pour justifier le montage.

## Vérifier sans jouer

```bash
godot --path jeu/godot --capture --quit-after 6000        # joue le chapitre en entier
godot --path jeu/godot ++ --scene i-02 --capture …        # un chapitre précis
godot --path jeu/godot ++ --scene i-26 --effets …         # regarde les effets
```

Le mode capture joue par `Input.parse_input_event`, donc par le chemin d'un vrai joueur.
Il imprime ce qu'il mesure et enregistre des images.

**Regarder les captures, toujours.** Rien ne mesure qu'un roi est décapité, qu'une réplique
déborde de son cadre, ou qu'un effet s'empile en auréole. Les trois sont arrivés.

**Un test ne joue pas la partie du joueur.** Le mode capture notait sa progression dans le
même fichier que la partie ; à force de vérifier la campagne, la sauvegarde s'est trouvée
poussée jusqu'au dernier chapitre, et le jeu s'ouvrait sur une bataille comme si toute
l'histoire avait été jouée. Les tests tiennent leur propre carnet
(`progression-essai.json`) — mais ils l'écrivent, sinon on ne vérifie plus l'enchaînement.

## Les pièges déjà payés

**Les fonctions anonymes de GDScript capturent par valeur.** Un compteur d'images
incrémenté dans une lambda ne monte jamais : les effets ne se libéraient pas, ils
s'empilaient, et l'empilement passait pour une auréole autour du personnage. Mettre l'état
mutable dans un dictionnaire, qui se capture par référence.

**Ne jamais nommer les planches à copier une par une.** La liste du lanceur est restée figée
sur deux fichiers pendant que dix existaient : le jeu se lançait sans Kira, sans la Reine,
sans les ennemis ni la neige de Shola. Rien ne le signalait — un personnage sans planche
paraît en silhouette, ce qui est un comportement prévu. On copie le dossier, pas une liste.

**GDScript n'a pas de commentaires en bloc.** `/* … */` fait échouer le chargement du script
entier, avec pour seul message « Expected statement, found "/" ».

**Les arguments du jeu passent après `++`.** Avant, Godot les revendique, et un mot sans
tiret y est pris pour un chemin de scène à charger.

**Le tri par profondeur ne met jamais une chose *dessous*, seulement *derrière*.** La mare
de sang, posée assez haut pour passer derrière Wellan, lui coiffait la tête comme un
capuchon rouge. Ce qui se pose au sol demande un plan explicite : le sol est à `z_index -2`,
ce qui s'y étale à `-1`, tout le reste à zéro. Et un `z_index` négatif sans avoir abaissé le
sol fait disparaître l'objet **sous** la carte de tuiles, tout en le laissant se déclarer
visible.

**Un `Control` ne participe pas au tri par profondeur** et se dessine dans l'ordre de
l'arbre. Les objets du décor sont des `Sprite2D`, sinon un meuble passe devant le joueur.

**Le tampon dessiné a un tour de retard sur l'état.** Une invite allumée dans la passe de
physique n'est pas encore peinte quand on capture : l'image montrait un coin vide et l'on
concluait qu'elle ne s'affichait pas. Attendre deux ou trois images avant de saisir.

**Deux affichages, non un.** La parole garde le cadre du bas, bordé d'or, avec le nom de qui
parle ; la description prend un bandeau large et centré, sans bordure ni nom, en italique et
en argent. Une page porte son genre (`parole` ou `recit`) — les confondre dans un même cadre
effaçait la différence et noyait les maladresses des personnages dans la narration.

**Un personnage abordé se tourne vers Wellan**, et garde ensuite cette orientation : se
détourner sitôt la conversation finie serait pire que ne s'être jamais tourné.

**Au démarrage, la compilation des shaders affame la physique.** Un test qui compte les
images ne garantit rien : attendre la condition.

**Ne pas nommer le dernier entré dans une zone de parole.** Six Chevaliers à deux tuiles les
uns des autres ont des cercles qui se recoupent : on retient tous ceux à portée et l'on
tranche par la distance, à chaque image.

**Le coup d'épée interroge l'espace** (`intersect_shape`) au lieu de poser une zone le temps
d'une image : un nœud créé puis détruit laisse la détection à la merci de l'ordre des images.

## Ce que le texte impose au combat

La fiche des hommes-insectes dit une carapace « les rendant invulnérables à la magie » : le
sort glisse sur eux, il faut le fer. Les dragons brûlent. Deux registres imposés par
l'œuvre, non choisis pour l'équilibre.

Un sort qui ne prend pas **poursuit sa course** au lieu de s'éteindre : c'est ainsi que le
joueur voit que ça ne prend pas.

## Les effets

Dessinés par calcul dans `build-jeu-donnees.ts`, pas générés : un arc et une braise sont des
formes exactes. `taillade.png` pointe vers l'est et le moteur la fait pivoter **par quarts de
tour** — à 90 degrés une image de pixel art tourne sans perdre un pixel.

Un arc trop mince passe pour un défaut d'affichage ; trop large en **angle**, il cerne le
personnage et se lit comme un halo. Le rayon donne l'allonge, l'angle donne le halo : pousser
le premier, retenir le second.

L'épaisseur suit un sinus le long de l'arc — large au milieu du geste, pincée aux deux bouts.
Un bandeau d'épaisseur constante flotte à côté du personnage comme une virgule détachée ; un
bandeau plein remplit le coin et se lit comme un bloc.

**La cellule contraint par sa hauteur, non par sa largeur** : au bout d'un arc ouvert à
soixante degrés, le rayon monte presque autant qu'il avance. Allonger le geste demande
d'agrandir la toile, non de pousser les nombres dans celle qu'on a.

**Relever la portée sur l'arc, jamais l'inverse.** La zone frappée couvrait de sept pixels
derrière Wellan à trente-sept devant pendant que la lame n'en atteignait que quatorze : on
touchait ce qu'on ne voyait pas atteindre, et le coup paraissait court. Un joueur juge la
portée sur ce qu'il voit.
