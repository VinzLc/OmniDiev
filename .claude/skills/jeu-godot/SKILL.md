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

## Les pièges déjà payés

**Les fonctions anonymes de GDScript capturent par valeur.** Un compteur d'images
incrémenté dans une lambda ne monte jamais : les effets ne se libéraient pas, ils
s'empilaient, et l'empilement passait pour une auréole autour du personnage. Mettre l'état
mutable dans un dictionnaire, qui se capture par référence.

**Les arguments du jeu passent après `++`.** Avant, Godot les revendique, et un mot sans
tiret y est pris pour un chemin de scène à charger.

**Un `Control` ne participe pas au tri par profondeur** et se dessine dans l'ordre de
l'arbre. Les objets du décor sont des `Sprite2D`, sinon un meuble passe devant le joueur.

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

Un arc trop mince passe pour un défaut d'affichage ; trop large, il cerne le personnage et
se lit comme un halo. Un quart de tour, près du corps.
