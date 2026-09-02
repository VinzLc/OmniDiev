---
name: oracle-site
description: Travailler sur l'Oracle et le site publié — l'application Next.js, le Codex, la Généalogie, les fiches de public/codex/, la publication GitHub Pages. À employer dès qu'il s'agit de toucher à components/, app/, lib/codex-view.ts, aux scripts build-codex/build-pages/build-site, ou de vérifier ce que le site montre vraiment.
---

# L'Oracle et le site

Deux visages du même corpus. **En local**, l'application entière : l'Oracle qui répond,
le Codex, la Généalogie. **Publié**, le Codex et la Généalogie seuls — l'Oracle a besoin de
routes serveur et de l'index de recherche, dont aucun ne quitte la machine.

```bash
npm run dev       # tout, avec les routes /api
npm run codex     # fiches, généalogies, puis pages
npm run pages     # public/codex/ et public/genealogie/ seuls
npm run site      # export statique dans out/, contrôle compris
npm run deploy    # npm run site, puis gh-pages
```

## Où vit quoi

| | |
|---|---|
| `lib/codex-view.ts` | la **seule** mise en forme des fiches : routes API et site statique |
| `scripts/build-pages.ts` | écrit `public/codex/index.json`, `public/codex/<id>.json` |
| `scripts/build-site.ts` | écarte `app/api/`, exporte, **contrôle**, remet les routes |
| `components/Codex.tsx` | la grille et le panneau de détail |
| `app/globals.css` | les jetons de couleur et toute la mise en forme |

`build-site.ts` écarte `app/api/` hors de `app/` le temps du build : un dossier qui y reste
est vu comme une route quel que soit son nom, et `output: "export"` les refuse. Elles sont
remises en place quoi qu'il arrive.

## Regarder ce qu'on publie

Le contrôleur mesure des octets. Il ne sait pas qu'une carte a perdu son visage, qu'un
portrait déborde, qu'un texte passe sous une image. **Il faut regarder** — la même règle que
pour les sprites, et il existe une façon de le faire sans quitter le terminal :

```bash
npm run build && npx next start -p 3111 &
until curl -sf http://localhost:3111/ -o /dev/null; do sleep 1; done

CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CH" --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1440,900 --screenshot=/tmp/vue.png \
  --virtual-time-budget=8000 \
  "http://localhost:3111/?tab=codex&fiche=wellan"
```

Puis lire `/tmp/vue.png`. `--virtual-time-budget` laisse les `fetch` du client aboutir : sans
lui on photographie une page vide et l'on conclut que rien ne s'affiche.

**Pour le mobile, cette recette ment.** `--window-size=390,844` rétrécit la fenêtre sans
émuler un téléphone : la capture montre une page coupée même quand la mise en page est
juste, et l'on part corriger un défaut qui n'existe pas. Il faut piloter Chrome par CDP et
poser `Emulation.setDeviceMetricsOverride` avec `mobile: true`. Node 22 porte un client
WebSocket, donc rien à installer :

```js
await envoie("Emulation.setDeviceMetricsOverride",
  { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
await envoie("Network.setCacheDisabled", { cacheDisabled: true }); // sur le site publié
```

Et **mesurer plutôt que regarder** pour le débordement horizontal : comparer
`documentElement.scrollWidth` à `clientWidth`, puis relever les éléments dont le
`getBoundingClientRect().right` dépasse. L'œil ne distingue pas une page qui déborde d'une
capture mal cadrée ; ces deux nombres, si.

Sur le site publié, le CDN sert parfois une feuille périmée alors que `curl` en reçoit la
neuve : un `flex-wrap` calculé à `wrap` là où la feuille téléchargée dit `nowrap` est un
cache, pas un bogue. `Network.setCacheDisabled` tranche.

**Les liens profonds rendent chaque écran atteignable** — c'est ce qui permet de viser une
fiche précise plutôt que de cliquer à l'aveugle :

| | |
|---|---|
| `?q=…` | pose la question à l'Oracle au chargement |
| `?tab=codex` · `?fiche=<id>` | ouvre le recueil, et la fiche |
| `?tab=genealogie` · `?arbre=<id>` | ouvre l'arbre |

Pour comparer deux états, découper les captures avec `sharp` et les coller côte à côte : un
seul aller-retour au lieu de deux.

## Ce qui ne se publie jamais

`build-site.ts` refuse de livrer et sort en erreur s'il trouve dans `out/` :

- `chunks.json`, `bm25.json`, `embeddings.bin` — ils portent le texte intégral des 44 volumes ;
- un motif `sk-ant-…` ou `gh[pousr]_…`.

**Ne pas contourner ce refus.** S'il se déclenche, c'est le contenu de `out/` qu'il faut
corriger — jamais le contrôle, dont le seul travail est de dire non.

## Un numéro, une fois

`ordered()` dans `lib/codex-view.ts` fixe l'ordre des fiches, donc leur numéro. Il est
**exporté et lu par `scripts/build-jeu-donnees.ts`** : « N° 062 » désigne Wellan sur le site
comme dans le Codex du jeu. Deux tris séparés auraient fini par diverger, et personne ne
l'aurait vu — c'est exactement le motif que `lib/books.ts` évite pour les volumes.

## Les portraits sur les cartes

Les visages sont dessinés pour le jeu et vivent dans `jeu/art/portraits/`. Le site en publie
une **copie** dans `public/codex/portraits/` : `public/` est ce que l'export emporte, et un
chemin vers un dossier de production ne survivrait pas à la publication.

**Un identifiant a le droit de porter un tiret.** `emeraude-ier` en porte un, et le filtre
qui prenait le tiret pour la marque d'une humeur (`wellan-grave.png`) l'a laissé sans
portrait — sur douze visages publiés au lieu de treize, personne ne compte. C'est la
correspondance avec un identifiant de fiche connu qui tranche, jamais la forme du nom.

**Réduire du pixel art par un rapport entier.** Les portraits font 128 ; la vignette de carte
fait 64, et non 56 ou 60. Sur un écran à densité double elle retrouve même le 1:1 exact. À
rapport fractionnaire, le voisin le plus proche mange une colonne sur trois et le visage
paraît sale sans qu'on sache pourquoi.

Un visage détouré a besoin d'un fond : sans panneau derrière, il flotte. Poser
`background: var(--surface-2)` sur la vignette, pas seulement sur la carte.

## Les pièges déjà payés

**Ajouter un champ à une fiche remue les 511 fichiers.** `git status` devient illisible et
l'on croit à un accident. C'est normal : `build-pages.ts` réécrit tout. Filtrer avec
`git status --short -- ':!public/codex'` pour retrouver ce qu'on a vraiment touché.

**`codexIndex()` et `codexDetail()` sont deux chemins.** Un champ ajouté à l'un manque à
l'autre, et le défaut ne se voit que sur le panneau de détail — c'est-à-dire après un clic
que personne ne fait en vérifiant la grille. Les modifier ensemble, toujours.

**Le site est un export statique.** Les images sont servies telles quelles ; une balise
`<img>` et `image-rendering: pixelated` suffisent, et il n'y a pas de configuration ESLint
pour s'en plaindre.

**Une valeur lue du disque se met en cache dans le module.** `aUnPortrait()` ne lit le
dossier qu'une fois : appelée 511 fois par construction, elle ferait sinon 511 `readdir`.
Mais le cache vit le temps du processus — un fichier ajouté pendant un `npm run dev` ne
paraîtra qu'au redémarrage.
