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

**`"pose": true` installe quelqu'un sans le faire entrer.** Toutes les scènes ne commencent
pas par une arrivée : Élund est dans sa tour quand on y monte, il n'y court pas derrière nous.
Sans ce drapeau, un personnage qu'une étape convoque traverse toujours la salle depuis un
seuil.

**On n'écrit que les chapitres où Wellan paraît.** Huit des treize chapitres restants du
tome I suivent quelqu'un d'autre — Chloé aux Fées, Santo à Argent, Dempsey à Cristal, Bergeau
à Zénor, Jasson chez les Elfes. Un jeu qui suit un seul protagoniste ne les joue pas, et le
`_chapitres` de `campagne.json` dit lesquels et pourquoi. Ce qu'ils contiennent d'essentiel
revient d'ailleurs par les rapports : le squelette de dragon du chapitre I,12 arrive dans la
bouche de Bergeau au chapitre I,15.

**Un lieu manquant se déclare dans `data/corrections.json`.** Le relevé des lieux est une passe
de lecture, et une passe de lecture oublie : le Royaume de Rubis n'y figurait pas, alors que
sept royaumes sont nommés dès le premier tome et que Wellan y est né. `lieuxAjoutes` le
rétablit avec son motif ; `build-jeu-donnees` l'applique **après** la boucle sur le Codex, de
sorte qu'un relevé futur reprenne la main. On ne corrige jamais `codex.json`, qui est produit.

**Un chapitre peut manquer d'un lieu.** Le Codex n'avait pas d'entrée pour le Royaume de Rubis,
alors même que Wellan y est né. Le mécanisme de corrections a été étendu pour le déclarer, et
le chapitre I,23 s'y joue — mais l'omission ne s'était vue qu'en voulant y placer une salle.

**Une salle peuplée appartient au chapitre qui l'a peuplée.** La clairière des Elfes porte les
six Chevaliers du chapitre I,6 ; y placer le chapitre I,13, où Wellan vient seul, les aurait
tous fait assister à la scène. Un autre endroit du même `lieu` coûte un fichier de données et
règle la contradiction — le village des Elfes n'est pas le camp.

**Le bloc `fin` est une étape comme les autres, condition comprise.** Sans `attend`, le
chapitre reste ouvert et n'appelle jamais le suivant — c'est le premier piège.

Les répliques sont **écrites**, jamais prélevées dans les romans : le dépôt est public.

**Tous les chapitres ne sont pas jouables tels quels.** Le roman coupe d'un lieu à l'autre ;
un jeu qui suit un seul protagoniste ne le peut pas. Le chapitre I,5 se joue au Château alors
que le résumé y met Wellan sur la route : la scène le ramène, et il devient l'un des cavaliers
qu'on envoie plutôt que l'un de ceux qu'on cherche à joindre. Le chapitre I,8 se partage entre
Émeraude et Shola : il est replié sur Shola, et la crise de Kira au Château arrive par la
télépathie sholienne qu'établit le chapitre I,5.

Replier ainsi ou sauter — mais le dire dans le champ `avertissement` de la scène, et
n'inventer aucun pouvoir pour justifier le montage.

## Ajouter une salle

1. Écrire `donnees/salles/<id>.json` — taille, terrain, mobilier, portes.
2. Percer une porte **des deux côtés** : `passages` porte `x`, `y`, `vers` et `arrivee`.
3. `npm run jeu:donnees` contrôle le tout et refuse une porte qui ment.

**Une porte ne porte pas de nom.** Elle dit `vers`, et l'invite lit le `nom` de la salle
visée chez elle. Recopier le nom dans la porte en ferait un second exemplaire, et deux
exemplaires d'un même nom divergent sans que personne le voie.

**Une porte peut n'ouvrir qu'à partir d'un chapitre.** `"des": "i-03"` et un `"verrou"` qui dit
pourquoi : l'escalier vers la chambre de Kira reste fermé aux chapitres I,1 et I,2, puisqu'elle
n'arrive qu'à la fin du premier. Une pièce meublée pour quelqu'un qui n'est pas encore là se
lit comme une faute de continuité.

**Le verrou se juge sur le chapitre qu'on joue, non sur le plus loin qu'on soit allé.** Rejouer
le I,1 doit retrouver la porte fermée, sinon le Château montre un état qui n'existait pas
encore.

**Une porte fermée se voit avant qu'on s'y heurte** : le battant perd ses couleurs et l'invite
annonce « Fermée » au lieu de nommer la destination. Nommer un endroit où l'on ne peut pas
aller est une promesse. Et la production **refuse** un `des` qui ne désigne aucun chapitre de la
campagne, ou un verrou sans motif — le joueur buterait sur un mur muet.

**Une porte tient sur un bord et dépose deux tuiles à l'intérieur.** À une tuile, la caméra
bute sur sa borne haute et l'on arrive décapité ; l'invite du retour s'allume aussi dès
l'arrivée, ce qui donne à croire qu'on n'a pas bougé.

**Le contrôle a deux registres, et c'est la différence qui compte.** Une porte qui vise une
salle absente, qui dépose hors du plancher ou qui n'a pas de retour est une **faute** : la
machine en juge seule, et le jeu casse. Deux meubles à moins de trois tuiles est un
**avertissement** : la règle est prudente, et il arrive qu'on ne se tienne jamais entre les
deux. Faire échouer la production là-dessus interdirait une mise en scène que personne n'a
regardée — sept voisinages anciens l'attendaient déjà au premier passage.

**Le mur reste plein derrière une porte.** Le battant est un dessin, pas une trouée : percer
la collision laisserait Wellan sortir dans le noir qui borde la salle, lequel n'est le sol de
rien.

**Rien sur la première rangée, sauf ce qui pend.** Un meuble en `y = 1` se dessine dans la
bande de mur et la caméra le coupe — vrai de toute salle plus haute que le cadre. Les
bannières font exception : elles pendent, c'est leur place.

**Une seule salle vit à la fois, et un registre dit qui est où.** `_effectif` survit à la
sortie ; les `apparaissent` et `disparaissent` d'une étape s'y inscrivent avant d'être joués,
et ne sont joués que si l'on est là pour les voir. Sans lui, la salle du trône se rebâtirait
d'après son fichier : Armène de retour alors qu'elle est repartie, la Reine absente alors
qu'elle vient d'entrer. Rien n'échoue, aucune erreur n'est levée — le chapitre ment.

**On ne franchit pas une porte tant qu'une vague est debout.** Fuir viderait le combat de son
enjeu, et laisserait des adversaires vivants dans une salle qu'on cesse de bâtir.

## Contrôler un chapitre, pas tout le jeu

```bash
npm run jeu:chapitres              # les dix-huit, sans fenêtre — 55 secondes
npm run jeu:chapitres -- i-23      # celui qu'on vient d'écrire — 6 secondes
```

Le parcours complet (`--capture`) éprouve le tour du Château, la musique, la course, le sac,
les commandes, les orientations, la pause. C'est ce qu'on veut avant de livrer ; c'est ruineux
quand on écrit un chapitre — vingt-six secondes et une fenêtre pour savoir si l'on a oublié de
poser Élund dans sa tour. Le mode `--verifier` ne répond qu'à une question par chapitre : **se
joue-t-il jusqu'au bout, et qu'est-ce qui manque ?**

**Il ne saisit aucune image, donc il tourne sans écran** — et c'est ce qui le rend dix fois
plus rapide, pas le fait de sauter des épreuves.

**Il relève la sortie d'erreur, pas seulement le résultat.** Un chapitre peut s'achever en
laissant derrière lui une fiche inconnue, une planche absente, un bruitage introuvable. C'est
ainsi qu'a été trouvé un appel à `_ui.jauges()` **avant que l'interface existe**, levé à chaque
lancement depuis l'arrivée des statistiques : sans effet visible, jamais vu, parce qu'on ne lit
pas la sortie d'erreur d'un jeu qui s'ouvre correctement.

**Et il ne regarde rien.** Aucune image ne dira qu'un roi est décapité ou qu'une réplique
déborde de son cadre. Pour cela le parcours complet reste le seul juge — les deux ne se
remplacent pas.

**Avant même Godot, `npm run jeu:donnees` refuse maintenant un chapitre injouable** : une étape
qui attend qu'on parle à quelqu'un d'absent de la salle, une clôture sans condition, une vague
défaite qu'aucune vague ne lève. La simulation d'effectif étape par étape servait déjà au
voisinage ; elle sert aussi à cela, et pour zéro seconde.

## Vérifier sans jouer

```bash
godot --path jeu/godot --capture --quit-after 6000        # joue le chapitre en entier
godot --path jeu/godot ++ --scene i-02 --capture …        # un chapitre précis
godot --path jeu/godot ++ --scene i-26 --effets …         # regarde les effets
```

Le mode capture joue par `Input.parse_input_event`, donc par le chemin d'un vrai joueur.
Il imprime ce qu'il mesure et enregistre des images.

**Une entrée de menu se reconnaît à son nom, jamais à son rang.** Intercaler « Codex » en
deuxième position aurait fait de « Sauvegarder » un retour à l'écran-titre : le `match` portait
sur `_choix_pause`. Le banc comptait ses appuis de la même façon — un `ui_down` puis
`ui_accept` — et aurait continué à passer en éprouvant autre chose. `match CHOIX_PAUSE[...]`
d'un côté, `_descendre_jusqu_a("Sauvegarder")` de l'autre.

**Une écriture ne rend jamais moins que ce qu'elle a trouvé.** `Partie.noter()` remplaçait
l'emplacement par `{ "chapitre": … }`. Tant qu'il n'y avait que le chapitre, personne ne
pouvait le voir ; le jour où le Codex y a rangé ses rencontres, une simple sauvegarde les
aurait effacées sans un mot. Compléter, jamais remplacer — la règle générale du projet,
appliquée au carnet.

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

**Une salle peut porter ses propres habitants.** Un `personnages[]` de salle accepte un `dit`
— des répliques qui vivent dans la salle et non dans une étape — et un `des` qui dit à partir
de quel chapitre il est là. C'est ce qui donne de la vie au monde : quelqu'un qui est là parce
qu'il habite là, non parce qu'une étape l'exige, et qui parle dans tous les chapitres qu'on y
joue.

**Le `des` d'un habitant obéit à la même règle que celui d'une porte** : Nogait est l'Écuyer de
Jasson et les Écuyers ne sont attribués qu'au chapitre I,15 — le trouver dans la galerie au
premier chapitre serait une faute de suite que rien d'autre ne signalerait. La production
refuse un `des` hors campagne, et une réplique dont le `qui` n'a pas de fiche.

**Leur clé d'écoute est `salle:<salle>:<fiche>`**, donc leur bulle s'éteint quand on les a
entendus, et le rattrapage d'après-clôture les inclut.

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

**Le Codex se remplit en parlant.** Le menu de pause l'ouvre ; un personnage s'y inscrit dès
qu'on lui adresse la parole — à l'abord, non à la fin de l'échange comme `_parles` : on a bel
et bien rencontré quelqu'un même en s'éloignant au milieu de sa phrase. Il porte le **numéro
du site** (voir **oracle-site**), et l'en-tête dit « 11 rencontres sur 365 » : un recueil sert
autant à montrer ce qui manque qu'à ranger ce qu'on a.

**Une partie neuve n'y trouve que Wellan.** Il s'inscrit sans qu'on lui adresse la parole —
on ne se rencontre pas soi-même — et c'est la seule fiche du recueil au premier pas.

**Et chaque entrée s'annonce.** `Partie.rencontrer` ne rend vrai que la première fois, ce qui
permet de ne le dire qu'une fois : un bandeau vert en bas à gauche et une montée de trois
notes. Une collection qui se remplit sans rien dire ne se sait pas — on n'ouvre pas un
recueil pour vérifier s'il a changé.

**Un écran qui couvre tout doit escamoter le reste.** Le premier Codex laissait les jauges de
vie et le rappel d'objectif flotter sur ses pages : ils sont ajoutés au `CanvasLayer` après
lui et se dessinent donc par-dessus. `interface.gd` retient ce qui appartient à la salle
(`_hud`) et l'éteint le temps de la consultation.

**Un test ne joue pas la partie du joueur.** Le mode capture notait sa progression dans le
même fichier que la partie ; à force de vérifier la campagne, la sauvegarde s'est trouvée
poussée jusqu'au dernier chapitre, et le jeu s'ouvrait sur une bataille comme si toute
l'histoire avait été jouée. Les tests tiennent leur propre carnet
(`parties-essai.json`) — mais ils l'écrivent, sinon on ne vérifie plus l'enchaînement.

## Les pièges déjà payés

**`queue_free` attend la fin de l'image, et les zones répondent jusque-là.** Les salles
partagent un repère : l'ancienne salle libérée mais encore dans l'arbre voyait Wellan
arriver à sa nouvelle place, et l'on se retrouvait à aborder quelqu'un qui n'est plus là,
dans une salle où il n'a jamais été. `remove_child` avant `queue_free`.

**Une porte dessinée vers le dehors ne se voit pas.** La caméra ne dépasse le plancher que de
huit pixels ; un battant de vingt-deux pixels posé derrière le mur tombait aux trois quarts
hors du cadre et se lisait comme un éclat de mur. La porte enjambe la ligne du mur, au plan
`-1` comme tout ce qui s'étale au sol.

**Un rappel de touche élargi doit voir son cadre suivre.** L'invite tenait « Espace » dans
quatre-vingt-seize pixels ; « La bibliothèque d'Élund › Espace » y perdait sa fin, sans
qu'aucune mesure ne le signale. C'est le même piège que les vingt-huit valeurs d'interface au
passage de 270 à 360 : rien ne mesure un texte coupé.

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

**GDScript réserve des mots qu'on n'attend pas.** `var trait := ColorRect.new()` fait échouer
le chargement du script entier sur « Expected variable name after "var" » — `trait` est
réservé pour un usage à venir. Le message ne nomme jamais le mot fautif.

D'où le réflexe qui coûte trois secondes au lieu d'un lancement complet :

```bash
godot --headless --path jeu/godot --check-only --script interface.gd
```

Il rend le fichier **et la ligne**. Sans lui, l'erreur remonte en cascade — `main.gd` se
plaint de ne pas pouvoir précharger `interface.gd`, et l'on cherche dans le mauvais fichier.

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

**Une épreuve qui tourne pendant la pause ne mesure rien.** Le contrôle des habitants était
placé au milieu des écrans de pause : la passe de physique sort avant de calculer un
interlocuteur, donc `_proche` restait vide et l'on concluait que l'habitant était hors de
portée alors qu'on se tenait sur lui. Rendre la main au jeu avant de mesurer.

**Un rappel de touches tronqué ne rappelle rien.** « Espace ou clic pour prendre · Échap pour
laisser » dépassait la largeur du cadre et se coupait à « Échap pour ». Deux fois de suite sur
deux écrans différents : la longueur d'une ligne d'invite se vérifie sur la capture, jamais
dans l'éditeur.

**Ajouter une icône décale toutes les autres.** `monde.prises[].image` est un rang dans
`inventaire.png`, et la planche se range par ordre alphabétique : deux icônes de plus, et
l'armure de cuir affiche un rouleau de parchemin. Le décalage ne se voit qu'à l'écran, et
seulement si l'on regarde. Réimporter après chaque `jeu:donnees` qui touche aux planches.

**Une planche neuve doit d'abord être copiée dans `assets/`.** `npm run jeu` copie
`jeu/art/personnages/` et `jeu/art/lieux/` dans `jeu/godot/assets/` avant de lancer ; un
`godot --path` appelé à la main saute cette étape. Deux jeux de tuiles neufs ont ainsi rendu
un sol **entièrement noir** — `load()` sur une ressource absente rend null, et une carte de
tuiles sans texture ne dessine rien, sans erreur. C'est le même piège que l'import, un cran
plus tôt dans la chaîne.

**Une planche neuve doit être importée avant d'être chargée.** `load()` sur une ressource que
Godot n'a pas encore vue rend null, et un Sprite2D sans texture ne dessine rien — sans erreur.
Le mobilier était absent de la salle et le décor semblait ne pas fonctionner.

**Au démarrage, la compilation des shaders affame la physique.** Un test qui compte les
images ne garantit rien : attendre la condition.

**Deux tuiles d'écart ne suffisent pas ; il en faut trois.** À égale distance de deux
voisins, on aborde l'un pour l'autre, et se rapprocher n'y change rien. Le défaut est revenu
trois fois — Kira contre sa mère, les six Chevaliers alignés, Kira contre Armène — et il
bloque une étape sans rien signaler.

**Un habitant peut donner, et le présent vient après la phrase.** Une entrée
`personnages[]` porte `dit` (ce qu'il raconte, qui vit dans la salle et non dans une étape),
`des` (le chapitre à partir duquel il est arrivé) et `donne` (une pièce, décrite exactement
comme le contenu d'un coffre). La fenêtre de butin s'ouvre à la dernière réplique — jamais
pendant : on écoute d'abord ce qu'il a à en dire. La production refuse un donneur muet, parce
qu'un présent sans un mot serait un ramassage déguisé.

**Le ton du jeu est volontairement maladroit.** Les personnages parlent trop littéralement,
changent de sujet sans transition, et disent la chose pratique là où l'on attend la chose
digne — « Ne me remerciez pas, je le transporte depuis onze jours ». Cela se lit comme une
traduction ratée, et **c'est voulu** : c'est ce qui fait rire. Le bandeau de récit, lui, reste
sobre — les deux registres ne se mélangent pas. Ne pas « corriger » ces répliques vers un
français plus soigné : ce serait effacer la voix du jeu.

**Une statistique sans pièce qui la touche n'existe pas pour le joueur.** La vitesse est
restée décorative jusqu'à ce qu'un emplacement `bottes` lui donne une prise. Ajouter un
emplacement coûte une ligne dans `emplacements` et une pose dans la poupée d'`interface.gd` —
mais les cases **flanquent** le sprite et ne le recouvrent jamais.

**Un chapitre porte son `ouverture` et sa `cloture`** : deux listes de phrases, dites dans le
bandeau des descriptions avant que l'étape commence et avant l'écran de fin.

**Les sortes de mobilier se lisent dans `monde.json`**, où la production les a inscrites
d'après le contenu de `jeu/art/objets/`. Ajouter un meuble ne demande qu'un PNG : ni liste
dans `main.gd`, ni liste dans le script. Une sorte inconnue dans une salle est refusée par
`npm run jeu:donnees` — sans quoi le moteur prendrait la première case de la planche et
poserait un arbre au milieu d'un dortoir.

**Le gros du décor est muet.** Sans `nom` ni `texte`, un meuble se dessine et ne s'aborde
pas — c'est ce qu'on veut de vingt arbres qui ferment une clairière, et cela les dispense de
la règle des trois tuiles, qui ne vaut que pour ce qui se dispute la touche de dialogue. Trois
ou quatre par salle suffisent à porter un texte ; un décor où chaque tronc se raconte fait un
musée, pas une forêt.

**Un meuble qui porte `contient` s'ouvre**, il ne se vide pas. La description d'abord ; quand
elle se referme, une fenêtre montre ce qu'il reste, pièce par pièce, avec son nom, ses bonus
en clair et son texte. **Rien n'entre dans le sac tant qu'on n'y a pas mis la main.** Tout
tombait auparavant dans la même phrase que la description, et l'on ne voyait jamais ce qu'on
ramassait.

**Le sac fait foi pour ce qui reste.** Une pièce déjà prise ne reparaît pas, et le coffre
s'ouvre vide plutôt que de se refermer sur rien.

**La souris survole et clique, le clavier aussi.** L'interface se contente d'émettre
`butin_survole` et `butin_pris` ; le jeu décide. Un écran qui exigerait la souris serait le
seul du jeu à le faire.

**L'infobulle se pose sous les cases, non au curseur.** Une bulle qui suit la souris n'a aucun
sens au clavier, et le jeu se joue au clavier. `contient` est toujours **une liste**, quitte à n'avoir
qu'un élément — le coffre des cuirs rend le plastron et le casque. `build-jeu-donnees`
rassemble tout dans `monde.prises` : la description s'écrit dans le meuble, mais le sac se lit
n'importe où, y compris dans une salle qui n'a jamais porté l'objet.

**Les deux catégories du sac ne se mélangent jamais.** Un `objet` se garde, un `equipement` se
porte, gauche et droite passent de l'une à l'autre. La production **refuse** un équipement sans
emplacement connu et un objet qui en porterait un : sans cette règle, presser Espace sur une
couverture l'« équiperait ».

## Le monde est ouvert

Le menu de pause porte **Carte** : le continent, sept escales, flèches pour viser, Espace pour
s'y rendre. La carte est **dessinée par calcul** (`lib/carte.ts` → `donnees/carte.png`) —
l'illustration publiée de l'œuvre est sous droits et le dépôt est public ; la disposition des
royaumes, elle, est un fait qu'on peut relever.

**Le dessin et les marques sortent de la même grille.** Une carte générée aurait obligé à
poser les marqueurs à l'œil par-dessus, et ils auraient dérivé à la première retouche.

**Achever un chapitre ne transporte plus personne.** Le suivant est noté, l'objectif devient
« Se rendre à *lieu* », et il ne s'ouvre que quand on y met le pied. On peut donc traîner,
revenir sur ses pas, vider un coffre — le chapitre patiente.

**La salle est retenue dans la partie**, au même titre que le chapitre : dans un monde ouvert,
l'endroit fait partie de l'avancement. Sans cela, chaque relance ramènerait au Château.

**Un chapitre imposé dépose à son départ.** `--scene`, et le rejeu depuis le menu, écrasent la
position gardée : « joue ce chapitre » veut dire « pose-moi là où il commence », sinon il
faudrait traverser la carte avant de pouvoir l'éprouver.

**Arriver dans un lieu où le chapitre attend dépose dans sa salle**, non à l'entrée du lieu :
le Château compte six pièces, et en traverser cinq après chaque voyage serait une corvée.

## Rejouer un chapitre

Le menu de pause porte **Chapitres** : la campagne entière, ceux qu'on n'a pas atteints
affichés éteints, et Espace pour rouvrir l'un des autres.

**La sauvegarde a gagné une marque d'avance qui ne redescend jamais.** Elle ne portait que
« où j'en suis » ; le jour où l'on rejoue le premier chapitre, « où j'en suis » vaudrait
soudain « chapitre un », et vingt-cinq chapitres d'avance disparaîtraient sans un mot.
`atteint` est le plus loin qu'on soit allé, `noter` ne le fait que monter, et les vieilles
sauvegardes qui ne le portent pas retombent sur le chapitre courant.

**Un chapitre rejoué se joue comme une scène imposée à la main** : `_libre` est vrai, rien ne
se note. `Partie.rejoue` est une **variable statique**, non une clé du carnet — c'est une
intention qui ne survit pas à la session, et l'inscrire dans la sauvegarde du joueur y
laisserait la trace de ce qui n'est pas sa progression. Elle est lue **avant** `--scene`, ce
qui ne change rien au lancement (elle y est toujours vide) et rend la branche éprouvable.

**Elle se consomme à la lecture.** Une fois le chapitre rejoué achevé, Entrée recharge la
scène, la variable est vide, et le joueur retombe exactement là où il en était.

**Un panneau se mesure à ce qu'il contient.** Le cadre de pause était haut de cent soixante
pixels, ce qui tenait quatre lignes. Au septième choix, « Sauvegarder » et « Écran-titre »
sont sortis du cadre — sans erreur, sans avertissement, et invisibles pour qui ne compte pas
les lignes sur la capture.

## Les statistiques

Cinq, à l'ancienne, et **chacune commande exactement un nombre du jeu** :

| | | |
|---|---|---|
| Force | `1 + (force − 5) / 5` | dégâts d'épée |
| **Vitesse** | `vitesse × 10` | pixels par seconde — elle remplace l'agilité, et se voit |
| Vitalité | `vitalité × 4` | points de vie |
| Sagesse | `= sagesse` | dégâts du sort |
| Défense | `défense / 6` | retranché à chaque coup reçu, jamais sous un point |

**La base reproduit l'équilibre d'avant à l'unité près** — 24 points de vie, 80 px/s, 1 dégât
d'épée, 7 de sort, aucune réduction. Ajouter des statistiques ne doit pas rééquilibrer le jeu
en douce : sinon on ne sait plus si un chapitre est devenu dur parce qu'il l'est, ou parce
qu'un chiffre a bougé sans qu'on regarde.

**Elles se recalculent à l'équipement, jamais à chaque image.** `Partie.equipe()` ouvre le
fichier de sauvegarde ; l'appeler soixante fois par seconde reviendrait à lire un disque pour
savoir à quelle vitesse marcher.

**Une statistique qui ne bouge que dans le tableau est une décoration.** Le banc mesure le
chemin parcouru au sol avant et après : le bouclier coûte un point de vitesse, et la marche
passe de 20 à 18 pixels sur trente images. C'est ça, la preuve — pas la ligne affichée.

**Wellan porte déjà quelque chose.** `monde.depart` déclare son épée et son surcot : deux
pièces qui ne sont dans aucun coffre, prises et équipées une seule fois au premier lancement —
comme il s'inscrit lui-même au Codex. `prendre` rendant faux ensuite, reposer son épée est
définitif et le jeu ne la remet pas de force.

**Leurs bonus ne changent aucun nombre du combat.** Force 5+3 rend toujours un dégât d'épée,
défense 2 toujours zéro de réduction. C'est voulu : donner un équipement de départ ne doit pas
rééquilibrer un jeu dont dix-huit chapitres ont été éprouvés à l'équilibre d'avant.

**L'onglet Équipements est une poupée d'habillage.** Le sprite de face au milieu, le casque
au-dessus, l'arme à gauche, le bouclier à droite, l'armure dessous. Une liste dit ce qu'on
possède ; elle ne dit pas de quoi l'on a l'air. Le cadre de l'emplacement visé s'allume en or,
ce qui relie la liste de gauche à la silhouette du centre.

**Ce qui appartient à quelqu'un ne se ramasse pas.** Les six coffres nommés du dortoir sont
ceux des six autres, le coffre fermé d'Élund reste fermé, et le coffre forcé du palais de
glace ne rend rien — « rien n'a été pris » est écrit dessus et c'est le sens de la salle. Le
jeu n'a rien à gagner à faire de Wellan un voleur au chapitre I,1.

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

## Les bruitages

Huit sons, **calculés** dans `lib/sons.ts` comme les effets sont dessinés — enveloppes sur du
bruit, glissandos, filtres. Rien n'est enregistré ni acheté : PCM 16 bits, mono, 22 050 Hz.
`sons.gd` les joue, le jeu dit seulement `_sons.jouer("epee")`.

| | |
|---|---|
| `epee` · `fer-touche` | le geste, puis le choc — le geste part même dans le vide, c'est ce qui apprend la portée |
| `sort` · `sort-touche` · `sort-glisse` | le feu part, le feu prend, la carapace refuse |
| `griffe` · `ennemi-meurt` | l'adversaire touche, l'adversaire tombe |
| `wellan-tombe` | le plus long et le plus grave : rien d'autre ne dure autant |

**`sort-glisse` énonce une règle du texte, il ne signale pas un raté.** La carapace des
hommes-insectes rend la magie inopérante ; on le voyait déjà, puisque le trait poursuit sa
course. Deux partiels volontairement faux l'un avec l'autre — rapport 1,51, qui ne tombe sur
aucun intervalle — pour que cela sonne le métal et ne ressemble à aucun autre son du jeu. Et
**une seule fois par trait** : sans le loquet `glisse`, il repart à chaque image de la
traversée et crépite.

**Un son ne se voit sur aucune capture.** C'est le seul élément du jeu dont une image ne dit
rien : fichier absent, import non fait, nom mal orthographié — le jeu se tait et l'on croit
qu'il est discret. La règle habituelle s'inverse, il n'y a rien à regarder et la mesure est
tout ce qu'on a. Le banc relève donc deux choses : `SONS n déclaré(s), n chargé(s)`, et le
compte de ce qui est parti.

**Et il les déclenche par la touche**, non par `jouer()`. Un appel direct prouve que le
fichier se joue, jamais que le jeu le joue au bon moment. `--effets` monte une vraie mêlée :
on frappe avec **J**, on lance avec **K**, on se laisse toucher, et l'on compare les
compteurs avant et après.

**Trente images entre deux coups, non huit.** `Combattant` accorde un répit de 0,45 s après
chaque blessure. À huit images le banc frappait dans le répit : douze coups ne portaient que
deux fois, l'adversaire ne tombait jamais, et `ennemi-meurt` passait pour débranché alors
qu'il marchait très bien.

**Viser la bonne chair.** La première vague de Zénor n'est faite que d'hommes-insectes, tous
carapacés : `sort-touche` ne pouvait pas partir. On cherche la vague qui porte des dragons
**par les espèces de la scène**, jamais par son rang — un rang est ce qui change quand on
réécrit un chapitre.

**Un adversaire se libère lui-même dans son signal `peri`.** `while cible.vivant()` sur la
référence gardée lève « Nonexistent function 'vivant' in base 'previously freed' », ce qui
interrompt la coroutine **sans rien faire échouer** : la moitié de l'épreuve ne tournait plus
et le relevé final donnait quand même les sons pour partis, puisque le rattrapage les jouait
directement. `is_instance_valid` sur toute référence gardée d'une image à l'autre.

**Les musiques sont séquencées, non calculées — et c'est une autre revendication.** Un coup
d'épée est une forme physique ; une mélodie est **écrite**. `lib/musiques.ts` compose deux
morceaux (`chateau-d-emeraude`, `ecran-titre`) en ré mineur, oscillateurs **à bande limitée**
— une onde carrée naïve grésille sur quarante secondes de mélodie et l'on rejetterait l'air
pour une raison qui n'est pas l'air.

**La musique d'un lieu est le fichier qui porte son nom.** `chateau-d-emeraude.wav` pour le
lieu `chateau-d-emeraude` : pas de table à tenir. Sans fichier au nom du lieu, le lieu est
muet. Une scène peut imposer le sien, pour le jour où une bataille aura le sien.

**Le morceau ne repart pas si c'est déjà le bon.** Franchir une porte du Château ne coupe pas
la phrase en cours ; sans ce test, le Château s'entendrait comme quatre salles séparées.

**La boucle se pose en images, dans le code, non dans le fichier d'import.** Le nombre
d'images vient de la production qui a rendu le morceau ; le déduire des octets marcherait
tant que l'import ne compresse pas. Et l'on éprouve le bouclage **sans attendre quarante
secondes** : on avance la tête de lecture juste avant la fin et l'on regarde si elle revient
au début.

**La traîne se replie sur le début.** Sans ce repli, la dernière note s'arrête net au
bouclage et l'on entend un clic toutes les quarante secondes — trop espacé pour qu'on
l'attrape, assez pour qu'on cherche une heure.

**Le contrôle de voisinage simule l'effectif étape par étape.** Comparer tous les
`apparaissent` d'un coup accusait Armène du chapitre I,1 de gêner Armène du I,2, et la Reine
de gêner une servante repartie une étape plus tôt : trois faux avertissements pour un vrai,
et l'on cesse de les lire. Le contrôle statique ne juge donc plus que le mobilier et les
portes — ce qui existe hors de tout chapitre.

**Un panneau se bâtit sur le gabarit du Codex, marge de contenu comprise.** Poser les enfants
avec des décalages à la main et une ancre droite à zéro ouvre un panneau **tout noir**, sans
une erreur ni un avertissement.

**L'invite appartient au HUD.** Elle flottait sur le sac ouvert : tout ce qui se dessine
par-dessus la salle doit céder la place à un écran qui couvre tout.

**Deux lueurs s'additionnent.** Wellan porte la sienne dès qu'une scène demande `lumieres` ;
un brasero à deux tuiles de lui crame le centre de la salle en blanc. C'est la même auréole
qu'on avait déjà payée sur les effets, par un autre chemin.

**Deux noms identiques dans deux fichiers qui se rencontrent.** `lib/carte.ts` exportait
`TEINTES` ; `build-jeu-donnees` en avait déjà un — les teintes de silhouette. L'import s'est
fait écraser **en silence** : le dépouillement de types de Node ne signale pas une double
déclaration, et le dessin est tombé sur « teinte is not iterable » à l'exécution. Renommé
`COULEURS`.

**Un trait de côte se peint arête par arête, non tout autour de la cellule.** Peindre l'anneau
complet de chaque cellule de rivage donnait un chapelet de perles : deux voisines dessinaient
chacune leur contour et la ligne se refermait à chaque pas.

**Une légende posée sur une carte a besoin d'un fond.** Elle se lisait par-dessus le désert et
la mer — deux fonds clairs — et disparaissait mot par mot selon l'escale visée.

**Un `Control` se dessine dans l'ordre de l'arbre.** L'écran des commandes bâti au milieu de
`_batir` passait **sous** le carton du chapitre, qui paraît au même instant à la première
partie : on n'en voyait qu'une ligne et demie. Il se pose en dernier.

**Le tableau BBCode de Godot serre sa seconde colonne.** Aligner les descriptions par
`[table=2]` repliait les lignes longues sous la première colonne et poussait le pied du
panneau hors du cadre. Un bord gauche irrégulier est le moindre défaut, sur sept lignes qu'on
lit une fois.

**Un objet fin sort maigre et délavé.** Une épée debout à 32 pixels rendait un bâton lavande :
la palette du monde n'a ni acier ni cuir, et un objet vertical n'occupe qu'une colonne. Le
remède est le même que pour la bannière — **coucher en diagonale, d'un coin à l'autre, et
exiger « chunky and heavy, not slender »**. Trois essais pour le trouver, puis huit réussites
d'affilée.

**Bannir le mot « chest » pour une armure de torse.** « A leather chest piece » a rendu un
coffre à trésor. Dire « body armour worn on the torso », « a cuirass », « armour for a body,
not a container ».

**La production refuse un son muet ou coupé net.** Un WAV de la bonne taille plein de zéros a
l'air d'un fichier correct — même durée, même en-tête, même poids à l'octet près. On relève
donc le sommet (pic ≥ 0,05) et le dernier échantillon (fin ≤ 0,02, sinon la coupure claque).
Le bruit est tiré d'une graine fixe : sans elle, huit binaires bougeraient à chaque production
sans qu'un octet de code ait changé.

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
