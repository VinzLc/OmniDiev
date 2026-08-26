# Charte

Ce que l'atelier a appris en produisant les premières images, et qui doit tenir pour les
suivantes. `CONTEXTE.md` dit ce qu'on demande à l'IA ; ce fichier dit ce qu'on accepte.

## Les échelles

| | Figure | Cellule |
|---|---|---|
| Chevalier | 24 × 30 px | 32 × 32 |
| Roi, civil | 16 × 31 px | 32 × 32 |
| Guerrier insectoïde | 14 × 31 px | 32 × 32 |
| Dragon | 31 × 21 px | 32 × 32 |

**Trente pixels de haut, jamais davantage.** Une figure plus grande ne rentre pas dans la
cellule et se fait rogner — le Roi y a perdu sa couronne au premier essai, et la planche est
passée au contrôleur sans un mot. `art:normalise` le signale désormais en rouge.

La largeur, elle, varie librement : un souverain en robe est plus étroit qu'un chevalier
cuirassé, et c'est ainsi qu'on les distingue à trente-deux pixels.

## Comment obtenir cette échelle

`npm run art:generer -- --creer <id> --taille 25`

**La taille demandée n'est pas la taille obtenue.** Commandé en 32, le Roi est sorti à 39.
Le préréglage de proportions grandit le personnage au-delà de la consigne. On commande donc
autour de 25, et l'on vérifie au recadrage.

| Option | Valeur | Quand |
|---|---|---|
| `--taille` | 25 à 27 | toujours ; 27 pour ce qui est large et bas |
| `--port` | `heroic` | humains et humanoïdes |
| `--port` | `default` | bêtes |
| `--gabarit` | `lion` | quadrupèdes ; `mannequin` par défaut |

`template_id` vaut déjà `mannequin` : ce n'est pas lui qui manquait aux deux premiers
échecs, c'étaient les proportions.

## Ce qui jure, et ce qu'on en fait

**Les silhouettes teintées ne sont pas un défaut**, c'est le dispositif : un personnage sans
planche paraît coloré d'après son identifiant, on lui parle, et le jour où son sprite
arrive, seule l'image change. Sur 365 personnages, 363 sont dans ce cas. Les faire attendre
reviendrait à ne jamais avancer.

**Les braseros sont des jalons**, un carré d'or cerclé de noir. Ils tiendront leur tuile.

**Les murs sont une bande sombre et des collisions**, faute de tuiles murales. Le jour où
elles arrivent, seul l'habillage change.

## L'ambiance

Une scène peut déclarer la sienne :

```json
"ambiance": { "teinte": "#5c6a90", "lumieres": true }
```

La teinte assombrit tout ; les braseros y percent des halos, et le personnage porte sa
propre lueur. **Wellan est vêtu de noir** : sans elle, il disparaît entre deux feux.

Le chapitre 26 place le débarquement dans la nuit. Le jouer en plein jour viderait la moitié
du texte de son sens — les fosses qu'on ne voit pas, les feux qu'on allume, la vague qui
arrive sans qu'on la distingue.

## Ce qui reste à faire

- 363 personnages en silhouette
- ni tuiles murales, ni mobilier, ni portraits de dialogue
- les dragons sont à l'échelle d'un chevalier alors que le texte les dit « deux fois plus
  gros qu'un cheval » — il faudra des cellules plus grandes, donc une planche par gabarit
