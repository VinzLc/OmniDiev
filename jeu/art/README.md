# Atelier graphique

Le circuit : **le texte commande, l'IA générative dessine, Godot consomme.**

```
data/index/codex.json  →  npm run art  →  commandes/<id>.md
data/raw/*.txt             (le script)     (à jouer dans l'outil génératif)
                                                    ↓
                                           sources/<id>/       le rendu brut, tel qu'il tombe
                                                    ↑          npm run art:generer (API PixelLab)
                                                    ↓          npm run art:normalise
                                           personnages/<id>.png   la planche que Godot lit
                                                    ↓          npm run art:verifier
                                              conforme, ou la liste de ce qui cloche
```

## L'ordre des opérations

1. **Une fois par session**, poser [`CONTEXTE.md`](CONTEXTE.md) dans l'IA graphique : le
   style, la palette du monde, les formats, le protocole de cohérence.
2. **Puis** jouer les commandes de `commandes/`, une par une.

Le contexte ne se répète pas dans chaque commande — c'est ce qui garantit que deux images
produites à des jours d'intervalle appartiennent au même jeu.

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

**Le rendu brut va dans `sources/<id>/`, tel que l'outil le livre** — arborescence, dossiers
d'états, `metadata.json`, sans rien réorganiser. Puis :

```bash
npm run art:normalise -- wellan    # sources/wellan/ → personnages/wellan.png
npm run art:verifier               # contrôle tout ce qui est destiné à Godot
```

L'identifiant est celui de la fiche du Codex : `wellan`, `chateau-d-emeraude`. Le nom du
dossier fait la liaison — aucun autre réglage n'est nécessaire.

| Étape | Emplacement | Forme |
|---|---|---|
| Rendu brut | `sources/<id>/` | ce que l'outil livre, intact |
| Planche assemblée | `personnages/<id>.png` | 128×128 — 4 colonnes × 4 rangées de 32×32 |
| Décors | `lieux/<id>.png` | tuiles de 16×16, planche de 16 colonnes |

Les rangées, dans l'ordre : **face, dos, profil gauche, profil droit**. Un outil qui ne rend
qu'une pose de repos remplit les quatre colonnes du même dessin — le sprite entre dans le
moteur sans marcher encore, et la planche se refait quand l'animation arrive.

## Commander directement à PixelLab

La clé va dans `.env.local` (`PIXELLAB_API_KEY=…`), qui est ignoré par git.

```bash
npm run art:generer -- --solde                                  # crédits restants
npm run art:generer -- --perso Wellan --action walking --frames 4
npm run art:generer -- --perso Wellan --action walking --directions south,north,east,west
```

**Une direction par défaut.** Engager les quatre doit être écrit — le service facture à la
génération, et le mode `pro` en consomme vingt à quarante *par direction*. La commande
annonce le solde avant, le coût après.

L'animation part du `character_id` déjà validé plutôt que d'une nouvelle description : c'est
ce qui garantit que le personnage animé soit le même que celui qu'on a accepté. La cohérence
cesse d'être une affaire de chance.

Mesuré sur Wellan : **une génération par direction** pour un cycle de quatre images, à
0 USD sur l'essai. L'API rend une toile de 44×44 là où le sprite en fait 32 — le
normaliseur recadre en calant sur la ligne de sol, jamais sur le centre géométrique, qui
décalerait le personnage.

## Ce que la normalisation fait aux couleurs

Elle aligne l'image sur la palette du monde, **sans l'y écraser**.

Une teinte colorée assez proche d'une couleur de `CONTEXTE.md` s'y range : c'est ce qui fait
que le vert de l'Ordre soit le même sur Wellan et sur le personnage dessiné trois semaines
plus tard. Une teinte colorée sans équivalent est conservée et signalée — à ajouter à la
palette si elle doit resservir.

**Les neutres, eux, ne sont jamais touchés.** Un noir n'a pas d'identité à unifier : deux
dessins s'accorderont d'eux-mêmes sur leurs gris. Les ranger de force ne servirait à rien et
leur ferait perdre leur teinte — le premier jet retournait ainsi le manteau vert-olive de
Wellan en noir violacé, parce qu'un gris de la palette se trouvait numériquement proche.

**Les quasi-jumelles sont fusionnées.** Deux états d'un même personnage ne reviennent pas
avec exactement les mêmes noirs : le repos porte `#222621`, la marche `#222620`. L'écart est
invisible et sans intention, mais chacune coûtait une place — onze des seize sur Wellan, si
bien qu'il ne restait rien pour les carnations et que le sprite avait le visage vert. Deux
teintes que l'œil ne sépare pas sont désormais une seule.

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
