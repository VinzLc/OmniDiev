# Atelier graphique

Le circuit : **le texte commande, l'IA générative dessine, Godot consomme.**

```
data/index/codex.json   →  npm run art  →  jeu/art/commandes/<id>.md
data/raw/*.txt              (le script)      (à jouer dans l'outil génératif)
                                                        ↓
                                          jeu/art/personnages/<id>.png
                                          jeu/art/lieux/<id>.png
```

## Produire des commandes

```bash
npm run art -- --lot etape0              # le lot minimal jouable
npm run art -- --perso kira --perso onyx # des personnages précis
npm run art -- --lieu zenor              # un lieu
```

Chaque commande contient le rôle du personnage (fiche du Codex), **les phrases des
romans qui décrivent son apparence**, la spécification technique, et le chemin du
fichier attendu en retour.

## Où déposer les images

| Type | Dossier | Format |
|---|---|---|
| Personnages | `jeu/art/personnages/<id>.png` | 128×128 — 4 colonnes × 4 rangées de 32×32 |
| Lieux | `jeu/art/lieux/<id>.png` | tuiles de 16×16, planche de 16 colonnes |

L'identifiant est celui de la fiche du Codex : `wellan`, `chateau-d-emeraude`. Le nom du
fichier fait la liaison — aucun autre réglage n'est nécessaire.

## Ce qui reste difficile

La génération d'images n'a pas supprimé le problème, elle l'a déplacé. Trois écueils, par
ordre de gravité :

1. **La cohérence d'une planche.** Seize images du même personnage doivent montrer la même
   personne. Les outils dérivent d'une rangée à l'autre. Parade : générer la rangée « face »
   d'abord, puis la fournir en référence pour les trois autres.
2. **Le raccord des tuiles.** Un décor dont les tuiles ne s'aboutent pas est inutilisable,
   quelle que soit sa beauté. À vérifier avant tout le reste.
3. **La discipline de palette.** Seize couleurs, aplats francs, pas d'anti-aliasing. Un
   sprite « joli » mais dégradé jurera avec tous les autres.

D'où l'ordre conseillé : portraits d'abord (le plus fiable), puis sprites en pose fixe,
puis cycles de marche, puis jeux de tuiles (le plus exigeant).
