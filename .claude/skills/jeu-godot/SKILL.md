---
name: jeu-godot
description: Travailler sur le jeu OmniDiev — le projet Godot de jeu/godot/, ses scènes de chapitre, son combat en temps réel, ses effets. À employer dès qu'il s'agit d'ajouter un chapitre, de toucher à main.gd, de vérifier que le jeu tourne, ou de comprendre pourquoi une animation ne joue pas.
---

# Le jeu

Flèches ou **WASD** pour marcher — `physical_keycode` vise la position de la touche, donc les
mêmes déclarations servent QWERTY et AZERTY. **J** l'épée, **K** le feu, **Espace** pour
parler, **Échap** la pause, **Entrée** le chapitre suivant.

```bash
npm run jeu                    # écran-titre, puis choix de la partie
npm run jeu -- --recommencer   # repartir du premier chapitre
npm run jeu -- --scene i-02    # un chapitre précis, sans toucher à la partie
```

## Où vit quoi

| | |
|---|---|
| `main.gd` | le jeu : la salle, le chapitre, le combat, les entrées |
| `interface.gd` | tout ce que le joueur lit par-dessus la scène |
| `partie.gd` | la sauvegarde, les emplacements, l'ordre des chapitres |
| `donnees.gd` | lire un JSON sans planter |
| `banc.gd` | le harnais de vérification |
| `titre.gd` | l'écran-titre et le choix de la partie |

**Le jeu ne touche plus un widget.** Il dit `_ui.parole(nom, texte, portrait)`,
`_ui.objectif(...)`, `_ui.acheve(...)` — où et comment cela s'affiche ne le regarde pas.
C'est ce qui permettra d'ajouter un inventaire ou une carte sans revenir dans `main.gd`.

**La sauvegarde n'existe qu'une fois.** L'écran-titre et le jeu en avaient chacun leur copie,
règle du carnet d'essai comprise : une divergence entre les deux aurait écrit dans la partie
du joueur pendant un test.

Tout est bâti en GDScript ; le `.tscn` n'accroche que le script. Un fichier d'éditeur écrit à la main dépend d'identifiants de ressources
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

**Le banc doit rendre ce qu'il emprunte.** L'épreuve de la pause choisissait « Sauvegarder »,
ce qui note le chapitre en cours — et écrasait donc l'avance que la fin du chapitre venait
d'inscrire. La campagne rejouait le premier chapitre à l'infini, et le défaut paraissait venir
du jeu.

**Regarder les captures, toujours.** Rien ne mesure qu'un roi est décapité, qu'une réplique
déborde de son cadre, ou qu'un effet s'empile en auréole. Les trois sont arrivés.

**Un écran qui attend une touche bloque le banc de test.** L'écran-titre attendait une
pression que personne ne fait en capture : le processus restait là sans erreur ni sortie
jusqu'au délai d'attente. `titre.gd` entre donc directement dans le jeu quand `--capture`,
`--effets` ou `--scene` sont là.

**Un personnage sans réplique écrite est muet, et ne s'aborde pas.** Le pis-aller récitait
sa fiche du Codex — son rôle puis la liste de ses liens. C'est de la documentation, pas du
jeu, et elle a déjà un endroit où vivre.

**Une fois le chapitre achevé, tout ce qui a été écrit redevient disponible.** Pendant le
chapitre, un personnage ne dit que ce que l'étape en cours lui donne ; après, on parcourt
toutes les étapes en commençant par ce qu'on n'a pas entendu. `_entendus` survit à l'étape là
où `_parles` est remis à zéro. C'est ainsi qu'on rattrape une réplique manquée sans rejouer
le chapitre — et il y en a beaucoup à manquer, puisque plusieurs ne sont exigées par aucun
objectif.

**Une salle se compose pour la caméra, non pour le plan.** Vingt-six sur quinze tassait tout
au milieu ; trente-deux sur vingt n'en montrait plus que six dixièmes et paraissait nue.
Vingt-huit sur dix-sept tient dans le cadre. Et ce sont les **pieds** du mobilier qui
s'alignent, jamais les sommets — une bannière monte plus haut qu'un brasero.

**La fin d'un chapitre n'arrête pas la partie.** Un panneau central qui prenait la main
coupait la salle au moment où l'on avait envie d'y traîner, et les répliques qu'aucun
objectif n'exige se perdaient. C'est un bandeau haut, et **Entrée** — non la touche de
dialogue — qui appelle la suite.

**Une bulle marque qui a quelque chose à dire.** Elle ne signale que la parole écrite par la
scène et pas encore entendue — une fiche du Codex se lit comme une description et reste
disponible indéfiniment, la signaler mettrait une bulle sur 365 personnages.

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

**Agrandir la vue se fait par le viewport, jamais par le zoom de la caméra.** Une caméra à
1,75 ferait rendre un sprite de 32 pixels sur 56 : les pixels cesseraient d'être carrés. Le
zoom reste entier et c'est la toile qui gagne du champ — 640×360 pour vingt tuiles de large.

Et **toute l'interface est réglée en pixels de viewport** : l'agrandir sans relever les
polices et les cadres la rapetisse d'autant. Vingt-huit valeurs ont dû suivre le passage de
270 à 360.

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

**Qui arrive ou s'en va le fait à pied.** `apparaissent` pose le personnage au seuil — celui
que la scène indique par `depuis`, ou le bord le plus proche — et il marche jusqu'à sa place ;
`disparaissent` le fait sortir de même. Un personnage qui surgit au milieu de la salle se lit
comme un défaut. Les marcheurs avancent avant tout le reste dans `_physics_process`, y compris
pendant un dialogue : une arrivée qui se fige parce qu'on lit une réplique se verrait aussitôt.

**Un personnage abordé se tourne vers Wellan**, et garde ensuite cette orientation : se
détourner sitôt la conversation finie serait pire que ne s'être jamais tourné.

**Une planche neuve doit être importée avant d'être chargée.** `load()` sur une ressource que
Godot n'a pas encore vue rend null, et un Sprite2D sans texture ne dessine rien — sans erreur.
Le mobilier était absent de la salle et le décor semblait ne pas fonctionner.

**Au démarrage, la compilation des shaders affame la physique.** Un test qui compte les
images ne garantit rien : attendre la condition.

**Deux tuiles d'écart ne suffisent pas ; il en faut trois.** À égale distance de deux
voisins, on aborde l'un pour l'autre, et se rapprocher n'y change rien. Le défaut est revenu
trois fois — Kira contre sa mère, les six Chevaliers alignés, Kira contre Armène — et il
bloque une étape sans rien signaler.

**Un chapitre porte son `ouverture` et sa `cloture`** : deux listes de phrases, dites dans le
bandeau des descriptions avant que l'étape commence et avant l'écran de fin.

**Un objet du décor devient examinable** dès qu'il porte un `nom` et un `texte`. Il entre dans
`_habitants` sous une clé `objet:x:y`, prend une zone de parole, mais n'a ni bulle ni
orientation : ce n'est pas quelqu'un.

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
