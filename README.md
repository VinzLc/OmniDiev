# L'Oracle d'Émeraude

Un bot qui connaît l'œuvre d'Anne Robillard — **Les Chevaliers d'Émeraude** (douze
tomes et son hors-série), **Les Héritiers d'Enkidiev**, **Les Chevaliers d'Antarès** et
**Légendes d'Ashur-Sîn**, 44 volumes indexés page à page — et qui répond en citant ses
sources.

Les quatre épopées forment un seul corpus : elles se suivent dans le même univers et
partagent des personnages. Une question sur Onyx traverse donc les quarante-quatre
volumes.

Tourne entièrement en local. Seule la génération des réponses passe par l'API Claude.

> **Les livres ne sont pas fournis.** Ce dépôt ne contient que la chaîne de traitement.
> Les romans d'Anne Robillard sont des œuvres sous droits : déposez vos propres
> exemplaires dans les dossiers `Epopée1/` … `Epopée4/`, que `.gitignore` exclut. Rien
> du texte des livres — ni les PDF, ni les extractions, ni l'index — n'est versionné.

---

## Le Codex en ligne

Les fiches d'entités sont publiées en site statique :
**[vinzlc.github.io/OmniDiev](https://vinzlc.github.io/OmniDiev/)**

Seul le Codex y figure — 511 fiches, du texte généré. L'index de recherche contient le
texte intégral des romans et ne quitte pas la machine ; l'Oracle, qui a besoin d'une clé
API, ne peut pas tourner sur un hébergeur statique. `npm run site` construit le site,
`npm run deploy` le publie, et la construction refuse de livrer si elle détecte un
secret ou un index de recherche dans la sortie.

## Démarrage

```bash
npm install

cp .env.example .env.local          # puis renseignez ANTHROPIC_API_KEY
                                    # (ou `ant auth login`, voir Authentification)
npm run ingest                      # extraction + découpage + embeddings (~25 min)
npm run codex                       # facultatif mais recommandé (~15 $, ~70 min)

npm run doctor                      # vérifie que tout est en place
npm run dev                         # http://localhost:3000
```

`npm run ingest` ne se relance qu'en cas de changement des PDF. Tout ce qui est
produit dans `data/` est régénérable et n'est pas versionné.

---

## Ce qu'il y a sous le capot

### La chaîne d'ingestion

```
Epopée1/*.pdf … Epopée4/*.pdf
   │  pdftotext -layout            l'indentation porte les alinéas,
   ▼                               isole les en-têtes et préserve la césure
data/raw/E1T00.txt … E4T07.txt
   │  réparation OCR (9 tomes)     les 35 tomes propres servent de dictionnaire
   │  parsing                      folios, chapitres, paragraphes
   │  découpage                    ~1 400 caractères, sans franchir un chapitre
   ▼
data/index/  chunks.json · bm25.json · embeddings.bin · codex.json
```

**19 842 fragments · 14 205 pages · 44 volumes.**

Le catalogue de [lib/books.ts](lib/books.ts) est l'unique source de vérité : l'extraction,
le parsing et l'interface en découlent. Chaque volume y porte un `order`, sa position
absolue dans l'ordre de lecture ; c'est sur lui que reposent la recherche, le tri et le
contrôle anti-divulgation, jamais sur le couple (épopée, tome). L'ordre du tableau fait
foi : c'est ce qui permet d'insérer un hors-série à sa place — « Les premiers
Chevaliers », préquel paru en 2023, se lit après le tome XII, et non avant le tome I
qu'il déflorerait.

Cinq problèmes concrets ont dicté la conception :

- **Les numéros de chapitre ressemblent aux folios.** Un `6` centré en haut d'une page
  et un `- 60 -` en bas ont la même forme. Le folio est *toujours* la dernière ligne non
  vide d'une page — jamais ailleurs. C'est ce qui les sépare.

- **…et un folio qui échappe au filtre est pire qu'inutile.** Les folios croissent
  régulièrement : ils forment la plus longue suite croissante possible et raflent la
  détection. Le tome 9 des Héritiers y gagnait 361 chapitres pour 461 pages. Un titre de
  chapitre ouvrant toujours une page, seules les premières lignes d'une page sont
  candidates — ce qui ramène le compte à 27.

- **Neuf tomes sur vingt-quatre sont des scans.** Plutôt qu'une table de corrections
  écrite à la main, les quinze tomes propres servent de dictionnaire de référence :
  accents perdus, apostrophes d'élision avalées, puis distance d'édition 1. Les formes
  inconnues tombent de ~11 % à ~3,5 %. La règle par distance d'édition est interdite sur
  les noms que le livre atteste lui-même en abondance : « Océani » est à une lettre
  d'« océan », et un nom revenu cinquante fois avec la même graphie est celui d'un
  personnage, pas une coquille. Détail dans [lib/ocr-repair.ts](lib/ocr-repair.ts).

- **Un compteur séquentiel de chapitres cale.** L'OCR ayant perdu le chapitre 1 du tome 8
  des Chevaliers, les cinquante suivants étaient rejetés. La détection retient la plus
  longue sous-suite croissante de numéros, ce qui absorbe les titres manquants.

- **Un livre ne doit jamais disparaître en silence.** Le découpage s'appuie sur le
  premier titre pour écarter les pages liminaires ; sans titre, aucun paragraphe n'était
  retenu et le volume entier était rejeté sans un mot. C'est arrivé aux deux premiers
  tomes d'Antarès, dont les titres de chapitre sont incrustés en image et n'existent donc
  pas dans la couche texte — un demi-million de caractères chacun. Faute de titre, c'est
  désormais une série ininterrompue de paragraphes de prose qui marque le début du roman :
  une page d'éditeur tient en un ou deux blocs isolés, le récit ne s'arrête plus.

- **Un titre de chapitre est centré, pas seulement indenté.** L'alinéa qui ouvre un
  paragraphe est indenté lui aussi. Plusieurs tomes d'Ashur-Sîn font suivre le numéro
  directement par le récit, et le seuil laxiste promouvait la première phrase du
  chapitre au rang de titre : « Chapitre 1 — Ce ne fut qu'à l'issue d'un terrible
  assaut de la part des Chevaliers ». Un titre se reconnaît à son centrage.

- **La page d'un paragraphe est celle où il commence**, quel que soit ce qui l'a ouvert.
  La rattacher au seul alinéa laissait à la page 1 tous les paragraphes des livres qui
  séparent leurs paragraphes par une ligne vide sans retrait — le tome III d'Ashur-Sîn
  citait ainsi 467 000 caractères comme s'ils tenaient sur une seule page.

- **Chaque épopée a sa mise en page.** L'en-tête courant alterne entre le nom de la saga
  et le titre du tome, et l'OCR le déforme d'une page à l'autre — « Les Héritiers
  d'Enkidiev » se lit tour à tour « lesderimersenkdev » ou « lesoueuxailes ». Coder les
  titres en dur ne tient pas : les en-têtes sont reconnus à leur récurrence, et leurs
  variantes déformées par proximité de trigrammes. De même, « Abussos » ne numérote pas
  ses chapitres — il les ouvre par un intitulé centré en capitales, motif reconnu à part.

### La recherche

Deux signaux fusionnés par [RRF](lib/retrieve.ts) — seuls les rangs sont combinés,
ce qui évite de calibrer deux échelles de score incomparables :

| | Points forts | Points faibles |
|---|---|---|
| **BM25** (lexical) | noms propres rares — « Amecareth », « Enlilkisar » | « Qui est Onyx ? » : le seul terme utile est le plus fréquent du corpus |
| **e5-small** (sémantique) | intention de la question, reformulations | confond deux scènes de bataille |

Les embeddings sont calculés **en local** (`@huggingface/transformers`, 384 dimensions) :
aucune seconde clé API, environ 6 minutes une fois pour toutes.

Un plafond de deux fragments par chapitre élargit la couverture : sans lui, une scène
longue monopolise le contexte alors que la réponse demande souvent de croiser les tomes.

### Le Codex

La recherche répond mal à « Qui est Onyx ? » parce que la réponse n'est écrite nulle
part en un seul endroit — elle est répartie sur douze tomes. Le Codex la précalcule,
en quatre passes ([scripts/build-codex.ts](scripts/build-codex.ts)) :

1. **Chapitres** — un résumé et les entités citées, pour chacun des ~1 195 chapitres.
2. **Fusion des identités** — le dépouillement nomme les personnages comme le fait le
   texte : « Amecareth » ici, « l'Empereur Noir » là ; « Abnar » et « le Magicien de
   Cristal » sont le même Immortel. Aucune similarité de chaîne ne peut les rapprocher,
   seul un lecteur du corpus le peut — cette passe consolide l'index avant d'écrire
   quoi que ce soit, sinon chaque fiche serait bâtie sur la moitié de ses mentions.
3. **Fiches** — toutes les mentions d'une entité fondues en une fiche : rôle, évolution,
   liens, tomes d'apparition.
4. **Synopsis** — un résumé par tome.

Chaque résultat intermédiaire est écrit dans `data/codex-cache/`, sous une clé qui cite
les tomes par leur identifiant et non par leur position — insérer un volume au milieu de
la série ne réinvalide donc pas les fiches inchangées. Une exécution interrompue reprend
sans repayer ce qui est déjà calculé.

```bash
npm run codex -- --dry-run          # estime le coût sans appeler l'API
npm run codex -- --saga 2           # se limite à une épopée
npm run codex -- --books 1,2        # se limite à des positions absolues
npm run codex -- --min-chapters 5   # relève le seuil d'entrée d'une entité
```

### La réponse

Les extraits sont envoyés en blocs `document` avec **citations activées** : Claude
renvoie la portion exacte du passage sur laquelle il s'appuie, ce qui rend la réponse
vérifiable au lieu d'être seulement plausible. Si l'API refuse ce format, la route
bascule automatiquement sans citations — `npm run doctor` indique lequel des deux
chemins sera emprunté.

Les fiches du Codex sont fournies séparément et explicitement marquées comme
non citables : ce sont des synthèses, pas le texte d'Anne Robillard.

### Le recueil

Un second onglet expose les fiches du Codex comme un bestiaire : numérotées dans
l'ordre d'entrée en scène — Abnar ouvre à 001, les figures d'Antarès referment —
filtrables par nature et par épopée, cherchables par nom ou par rôle.

Chaque fiche donne la description, l'évolution à travers la saga, les volumes
d'apparition et les **liens vers les autres fiches** : les relations sont résolues
côté serveur, si bien qu'on navigue de Sierra à Audax puis à Wellan sans repasser par
la recherche. L'index allégé (136 Ko) part d'un bloc — filtres et recherche sont donc
instantanés — et le détail se charge à la demande.

Le sélecteur « J'ai lu jusqu'à… » s'y applique aussi : les fiches dont l'entrée en
scène est encore à venir disparaissent du recueil.

### Liens profonds

- `/?q=Qui%20est%20Onyx%20%3F` — pose la question au chargement
- `/?tab=codex` — ouvre le recueil
- `/?fiche=sierra` — ouvre une fiche précise

### Le contrôle anti-divulgation

Le sélecteur « J'ai lu jusqu'à… » couvre les deux épopées d'un seul tenant et agit à
deux niveaux : la recherche ignore tout ce qui suit la position choisie, et le prompt
système interdit d'en rien révéler. Utile pour une lecture en cours.

---

## Commandes

| Commande | Effet |
|---|---|
| `npm run dev` | serveur de développement |
| `npm run doctor` | vérifie index, clé API, citations, sorties structurées, recherche |
| `npm run ingest` | `extract` + `corpus` + `embed` |
| `npm run extract` | PDF → texte brut (nécessite `poppler`) ; `-- --saga 2` pour une seule épopée |
| `npm run corpus` | texte → fragments + index BM25 |
| `npm run embed` | fragments → vecteurs (local, ~17 min) |
| `npm run codex` | construit le Codex (API Claude) |
| `npm run build` / `npm start` | build et serveur de production |
| `npm run site` | construit le site statique du Codex dans `out/` |
| `npm run deploy` | construit puis publie sur la branche `gh-pages` |

## Authentification

Le code construit toujours un client nu — `new Anthropic()` — qui suit la chaîne
d'identifiants du SDK et prend le premier disponible :

```
ANTHROPIC_API_KEY  →  ANTHROPIC_AUTH_TOKEN  →  profil OAuth  →  profil par défaut
```

Deux voies, donc, au choix :

**Une clé API.** `ANTHROPIC_API_KEY` dans `.env.local`. C'est le plus direct.

**Un profil OAuth**, sans clé statique à gérer :

```bash
brew install anthropics/tap/ant
xattr -d com.apple.quarantine "$(brew --prefix)/bin/ant"
ant auth login          # ouvre le navigateur, dépose un profil dans ~/.config/anthropic/
ant auth status         # montre quelle source l'emporte
```

Trois pièges, tous vérifiés ici :

- **Un profil n'est consulté que si aucune clé n'est définie.** Une `ANTHROPIC_API_KEY`
  exportée ailleurs dans votre shell masque silencieusement le profil.
- **Une clé vide n'est pas neutre** : `ANTHROPIC_API_KEY=` occupe le premier rang de la
  chaîne et authentifie avec une clé vide. [lib/env.ts](lib/env.ts) ignore désormais les
  valeurs vides pour cette raison ; commentez la ligne plutôt que de la vider.
- **Conflit possible avec Claude Code**, qui honore la même résolution de profils :
  après `ant auth login`, il peut signaler un conflit avec sa propre connexion. Gardez-en
  une seule — soit le profil (`/logout` dans Claude Code), soit la connexion de Claude
  Code (`ant auth logout`).

`npm run doctor` affiche la source retenue et signale ces conflits.

> Ce choix porte sur la **façon de s'authentifier**, pas sur ce qui est facturé : dans
> les deux cas les requêtes partent vers l'API Anthropic, sous l'organisation et le
> workspace auxquels l'identifiant est rattaché. Vérifiez la consommation dans votre
> console Anthropic.

## Configuration

| Variable | Défaut | Rôle |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | requise, sauf si un profil OAuth est actif |
| `ANTHROPIC_PROFILE` | `default` | profil OAuth à utiliser |
| `OMNIDIEV_MODEL` | `claude-opus-5` | modèle de conversation |
| `OMNIDIEV_CODEX_MODEL` | `claude-haiku-4-5` | modèle de construction du Codex |
| `OMNIDIEV_EFFORT` | `medium` | profondeur de raisonnement (`low` → `max`) |

## Dépendances système

`pdftotext`, fourni par poppler :

```bash
brew install poppler
```

---

## Structure

```
lib/          books · parse · ocr-repair · chunk · text · bm25 · embed
              retrieve · codex · prompt · claude · pool · env
scripts/      extract.sh · build-corpus · build-embeddings · build-codex · doctor
app/          page · layout · globals.css
              api/chat · api/status · api/codex · api/codex/[id]
components/   Sigil · Answer · Sources · Codex
data/         raw/ · index/ · codex-cache/        (régénérables, non versionnés)
Epopée1/      les 12 PDF sources                  (non versionnés)
```

## Ajouter une épopée

Les épopées suivantes se branchent sur la même chaîne :

1. Déposer les PDF dans un dossier frère de `Epopée1/`.
2. Ajouter la saga et ses tomes dans [lib/books.ts](lib/books.ts) — et rien d'autre :
   l'extraction, le parsing, l'interface et le sélecteur en découlent.
3. Relancer `npm run ingest`, puis `npm run codex` si vous l'utilisez.

Le parsing ne dépend d'aucune particularité d'une épopée : les en-têtes courants sont
reconnus à leur récurrence, et la détection de chapitres couvre les trois mises en page
rencontrées (numéro seul sur sa ligne, `1. Titre` en ligne, intitulé centré sans
numéro). Marquez un tome `quality: "scan"` pour lui appliquer la réparation OCR, et
laissez `"clean"` les éditions dont la couche texte est saine — ce sont elles qui
fournissent le dictionnaire de référence.

## Limites connues

- **Les neuf tomes scannés** gardent ~3,5 % de formes mal océrisées, et une partie de
  leurs titres de chapitre reste illisible (les numéros et les pages restent justes).
- **Chapitres manqués dans les scans** : quand l'OCR détruit un numéro, les fragments
  suivants héritent du libellé du chapitre précédent. La référence de page, elle, reste
  exacte — c'est elle qui permet de vérifier.
- **Plusieurs volumes n'ont ni folio ni en-tête** dans leur couche texte — les tomes X et
  XII des Héritiers, le hors-série, et toute l'épopée d'Antarès : leurs références
  renvoient au numéro de page du PDF, non à celui de l'édition papier.
- **Les tomes I et II d'Antarès n'ont aucun découpage en chapitres** : leurs titres sont
  incrustés en image. Les livres sont indexés d'un seul tenant, et leurs citations portent
  la mention « Hors chapitre ». Les pages, elles, restent exactes. Leurs positions
  seraient récupérables via `pdfimages` si le découpage devenait nécessaire.
- **23 fragments sur 16 876** commencent par une lettrine perdue par l'OCR
  (« e monde céleste » pour « Le monde céleste ») — 0,14 %, dans les scans.
- Les prologues des tomes 9 à 12 récapitulent les tomes précédents : le même texte
  apparaît donc dans plusieurs tomes, et la recherche peut le remonter en double.
- Les vecteurs sont tronqués à 512 tokens par fragment ; la fin des fragments les plus
  longs ne pèse que sur la recherche lexicale.
- Le Codex garde deux fiches pour Nomar et Akuretari, qui sont le même Immortel — la
  saga ne le révèle que tardivement, et la passe de fusion s'abstient dans le doute
  plutôt que de risquer de fondre deux personnages distincts.
- `npm audit` signale des vulnérabilités dans `postcss` et `sharp`, atteintes par des
  dépendances transitives de Next et de transformers.js. Sans entrée non fiable et en
  usage purement local, elles ne sont pas exploitables ici.
