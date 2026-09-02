/**
 * Transforme un rendu brut d'IA graphique en planche exploitable par Godot.
 *
 * L'outil rend une arborescence : un dossier par état, un PNG par rotation,
 * dans les teintes qu'il a bien voulu choisir. Le moteur, lui, attend une
 * planche unique de 128×128 aux rangées ordonnées. Entre les deux, deux
 * opérations mécaniques — ramener les couleurs sur la palette du monde, et
 * assembler.
 *
 * Le ramenage n'est pas cosmétique. Un personnage isolé peut bien porter le
 * vert qu'il veut ; c'est quand le deuxième arrive, avec son propre vert, que
 * le monde cesse de tenir ensemble. La palette commune est ce qui fait qu'des
 * images produites séparément appartiennent au même jeu.
 *
 * Usage :
 *   npm run art:normalise -- wellan
 *   npm run art:normalise                 tout jeu/art/sources/
 */
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";

const ROOT = path.resolve(import.meta.dirname, "..");
const ART = path.join(ROOT, "jeu", "art");
const SOURCES = path.join(ART, "sources");
const OUT = path.join(ART, "personnages");
const LIEUX = path.join(ART, "lieux");

const SPRITE = 32;
const TUILE = 16;
const COLS = 4;
const MAX_COLORS = 16;

/** Ordre des rangées, celui qu'attend le moteur. */
const ROWS = ["south", "north", "west", "east"] as const;
const ROW_LABEL = { south: "face", north: "dos", west: "profil gauche", east: "profil droit" };

/** Tous les noms de direction, les composés d'abord — « south-east » contient « south ». */
const DIRECTIONS = [
  "south-east", "south-west", "north-east", "north-west",
  "south", "north", "east", "west",
];

const C = { red: "\x1b[31m", yellow: "\x1b[33m", green: "\x1b[32m", dim: "\x1b[2m", off: "\x1b[0m" };

type RGB = [number, number, number];

/**
 * La palette du monde, lue dans CONTEXTE.md.
 *
 * Elle y est écrite pour l'IA graphique ; la relire ici plutôt que d'en tenir
 * une seconde copie évite qu'un jour les deux divergent sans que personne le
 * remarque — le genre de dérive silencieuse qui ne se voit qu'au dixième
 * personnage.
 */
function worldPalette(): RGB[] {
  const src = fs.readFileSync(path.join(ART, "CONTEXTE.md"), "utf8");
  const hexes = [...new Set(src.match(/#[0-9A-Fa-f]{6}\b/g) ?? [])];
  if (hexes.length < 8) throw new Error(`Palette introuvable dans CONTEXTE.md (${hexes.length} teintes)`);
  return hexes.map((h) => [
    parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16),
  ] as RGB);
}

/**
 * Distance perceptuelle, via Oklab.
 *
 * La distance euclidienne en RVB ne dit rien de ce que l'œil voit : elle juge
 * deux bleus sombres très éloignés et deux verts vifs très proches. Snapper une
 * palette là-dessus délave les ombres et écrase les teintes vives. Oklab range
 * les couleurs comme on les perçoit, ce qui est précisément ce qu'on veut ici.
 */
function oklab([r, g, b]: RGB): RGB {
  const lin = (c: number) => { const v = c / 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  const R = lin(r), G = lin(g), B = lin(b);
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

function nearest(c: RGB, palette: RGB[], lab: RGB[]): number {
  const [L, A, B] = oklab(c);
  let best = 0, dist = Infinity;
  for (let i = 0; i < palette.length; i++) {
    const d = (lab[i][0] - L) ** 2 + (lab[i][1] - A) ** 2 + (lab[i][2] - B) ** 2;
    if (d < dist) { dist = d; best = i; }
  }
  return best;
}

type Frame = { data: Buffer; width: number; height: number; channels: number };

async function readPng(file: string): Promise<Frame> {
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return fit({ data, width: info.width, height: info.height, channels: info.channels });
}

/**
 * Ramène une image à la taille du sprite, calée sur le sol.
 *
 * L'API d'animation rend une toile plus large que la pose de repos — 44×44 pour
 * un sprite de 32 — afin de laisser de l'air au mouvement. Recadrer au centre
 * géométrique décalerait le personnage ; on cale donc sur ce qui compte, la
 * ligne de sol, et on centre horizontalement sur le contenu. Les images d'une
 * même direction retombent ainsi exactement où était le repos.
 */
/** Ce qui n'est pas entré dans la cellule, relevé au fil du recadrage. */
let debordements: string[] = [];

function fit(f: Frame): Frame {
  if (f.width === SPRITE && f.height === SPRITE) return f;

  let top = f.height, bottom = -1, left = f.width, right = -1;
  for (let y = 0; y < f.height; y++) {
    for (let x = 0; x < f.width; x++) {
      if (f.data[(y * f.width + x) * f.channels + 3] < 16) continue;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
      if (x < left) left = x;
      if (x > right) right = x;
    }
  }
  if (bottom < 0) return { data: Buffer.alloc(SPRITE * SPRITE * 4, 0), width: SPRITE, height: SPRITE, channels: 4 };

  /*
   * Une figure trop grande pour la cellule doit se signaler, non se laisser
   * rogner.
   *
   * Le Roi est sorti à 39 pixels de haut là où la cellule en fait 32 : calé sur
   * le sol, il a perdu sa couronne et sa tête, et la planche est passée au
   * contrôleur sans un mot. Rien ne mesure qu'un roi est décapité — il faut le
   * dire ici.
   */
  const hauteur = bottom - top + 1, largeur = right - left + 1;
  if (hauteur > SPRITE || largeur > SPRITE) {
    debordements.push(`${largeur}×${hauteur}`);
  }

  /* Le repos occupe la toile jusqu'à un pixel du bas : on reproduit cette
   * assise plutôt que de coller le personnage au bord. */
  const ox = Math.round(left - (SPRITE - (right - left + 1)) / 2);
  const oy = bottom - (SPRITE - 2);

  const out = Buffer.alloc(SPRITE * SPRITE * 4, 0);
  for (let y = 0; y < SPRITE; y++) {
    for (let x = 0; x < SPRITE; x++) {
      const sx = x + ox, sy = y + oy;
      if (sx < 0 || sy < 0 || sx >= f.width || sy >= f.height) continue;
      const si = (sy * f.width + sx) * f.channels, di = (y * SPRITE + x) * 4;
      out[di] = f.data[si]; out[di + 1] = f.data[si + 1];
      out[di + 2] = f.data[si + 2]; out[di + 3] = f.data[si + 3];
    }
  }
  return { data: out, width: SPRITE, height: SPRITE, channels: 4 };
}

/**
 * Seuil d'adoption, en distance Oklab.
 *
 * En deçà, deux teintes sont assez proches pour que les confondre serve la
 * cohérence sans se voir. Au-delà, les confondre détruit du modelé.
 */
const SNAP = 0.12;

/**
 * En dessous de cette chroma, une couleur est un neutre — et on n'y touche pas.
 *
 * C'est la leçon du manteau de Wellan. Son vert olive sombre (chroma 0.011)
 * trouvait à 0.038 un gris violacé de la palette : assez près pour passer le
 * seuil, assez loin pour retourner la teinte. Le manteau devenait noir.
 *
 * Un neutre n'a rien à unifier. Deux personnages dessinés séparément
 * s'accorderont d'eux-mêmes sur leurs noirs et leurs gris ; c'est sur le vert
 * de l'Ordre, l'or de la croix, le mauve de Kira qu'ils divergeront. Le
 * ramenage ne doit porter que là — sur ce qui porte une identité.
 */
const NEUTRAL = 0.05;

/**
 * En deçà de cette distance, deux teintes sont la même et ne doivent pas coûter
 * deux places.
 *
 * Un outil qui rend deux états d'un même personnage ne redonne pas exactement
 * les mêmes noirs : le repos porte #222621, la marche #222620. L'écart est
 * invisible et sans intention. Laissés distincts, ces jumeaux ont occupé onze
 * des seize places de Wellan — il ne restait rien pour les carnations, qui se
 * sont repliées sur la teinte survivante la plus proche, un vert. Le sprite
 * avait le visage vert.
 */
const MERGE = 0.03;

type SnapStat = { before: number; after: number; adopted: string[] };

/**
 * Aligne les couleurs sur la palette du monde — sans écraser ce qu'elle ne
 * couvre pas.
 *
 * Le premier jet ramenait tout, de force, sur les vingt-cinq teintes de
 * CONTEXTE.md. Résultat : la vue de dos, dont le modelé vit entier sous L=114
 * alors que la palette n'y propose que six marches, perdait son relief. La
 * palette avait été écrite comme consigne de génération, pas comme cible de
 * quantification ; s'en servir ainsi était une erreur.
 *
 * Elle sert donc de point d'ancrage, non de lit de Procuste. Une teinte proche
 * d'une couleur du monde s'y range — c'est ce qui fera que le vert de l'Ordre
 * soit le même d'un personnage à l'autre. Une teinte qui n'a pas d'équivalent
 * est adoptée telle quelle, et signalée : c'est la palette qui doit s'étendre,
 * pas l'image qui doit s'appauvrir.
 */
function snap(frames: Frame[], palette: RGB[]): SnapStat {
  const lab = palette.map(oklab);
  const before = new Set<string>();
  const map = new Map<number, RGB>();
  const adopted: string[] = [];

  const key = (r: number, g: number, b: number) => (r << 16) | (g << 8) | b;
  const hex = ([r, g, b]: RGB) => `#${[r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")}`;

  /* Chaque teinte source : rangée si une couleur du monde est assez proche,
   * conservée sinon. */
  for (const f of frames) {
    for (let i = 0; i < f.width * f.height; i++) {
      const o = i * f.channels;
      if (f.data[o + 3] < 16) continue;
      const k = key(f.data[o], f.data[o + 1], f.data[o + 2]);
      before.add(String(k));
      if (map.has(k)) continue;
      const src: RGB = [f.data[o], f.data[o + 1], f.data[o + 2]];
      const [L, A, B] = oklab(src);

      // Neutre : conservé tel quel, aucune identité à aligner. Rien à signaler,
      // c'est le comportement voulu — seule une teinte colorée sans équivalent
      // mérite qu'on avertisse.
      if (Math.hypot(A, B) < NEUTRAL) { map.set(k, src); continue; }

      let best = 0, dist = Infinity;
      for (let p = 0; p < palette.length; p++) {
        const d = Math.sqrt((lab[p][0] - L) ** 2 + (lab[p][1] - A) ** 2 + (lab[p][2] - B) ** 2);
        if (d < dist) { dist = d; best = p; }
      }
      if (dist <= SNAP) map.set(k, palette[best]);
      else { map.set(k, src); adopted.push(hex(src)); }
    }
  }

  /*
   * Réduction à seize teintes — sur la part que chacune occupe dans l'image où
   * elle pèse le plus, non sur son total.
   *
   * Compter les totaux revenait à faire voter les frames claires contre les
   * sombres : une teinte qui couvre la moitié d'une vue de dos, mais n'existe
   * nulle part ailleurs, perdait contre une teinte tiède présente partout. La
   * part maximale protège ce qui construit une image, fût-ce une seule.
   */
  const share = new Map<string, number>();
  for (const f of frames) {
    const local = new Map<string, number>();
    let opaque = 0;
    for (let i = 0; i < f.width * f.height; i++) {
      const o = i * f.channels;
      if (f.data[o + 3] < 16) continue;
      opaque++;
      const h = hex(map.get(key(f.data[o], f.data[o + 1], f.data[o + 2]))!);
      local.set(h, (local.get(h) ?? 0) + 1);
    }
    if (!opaque) continue;
    for (const [h, n] of local) share.set(h, Math.max(share.get(h) ?? 0, n / opaque));
  }

  /*
   * Fusion des quasi-jumelles, la plus portante l'emportant. C'est le geste
   * qu'un pixel-artiste fait à la main : deux noirs qu'on ne distingue pas sont
   * un seul noir.
   */
  const ranked = [...share.entries()].sort((a, b) => b[1] - a[1]);
  const toRgb = (h: string): RGB => [
    parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16),
  ];
  const reps: { hex: string; lab: RGB }[] = [];
  const merged = new Map<string, string>();
  for (const [h, weight] of ranked) {
    const l = oklab(toRgb(h));
    const near = reps.find((r) => Math.hypot(r.lab[0] - l[0], r.lab[1] - l[1], r.lab[2] - l[2]) <= MERGE);
    if (near) {
      merged.set(h, near.hex);
      share.set(near.hex, Math.max(share.get(near.hex) ?? 0, weight));
    } else {
      reps.push({ hex: h, lab: l });
      merged.set(h, h);
    }
  }

  const kept = reps
    .map((r) => r.hex)
    .sort((a, b) => (share.get(b) ?? 0) - (share.get(a) ?? 0))
    .slice(0, MAX_COLORS);
  const keptRgb: RGB[] = kept.map((h) => [
    parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16),
  ]);
  const keptLab = keptRgb.map(oklab);
  const final = new Map<number, RGB>();
  for (const [k, rgb] of map) {
    const rep = merged.get(hex(rgb)) ?? hex(rgb);
    final.set(k, kept.includes(rep) ? toRgb(rep) : keptRgb[nearest(rgb, keptRgb, keptLab)]);
  }

  for (const f of frames) {
    for (let i = 0; i < f.width * f.height; i++) {
      const o = i * f.channels;
      if (f.data[o + 3] < 16) { f.data[o + 3] = 0; continue; }
      const [r, g, b] = final.get(key(f.data[o], f.data[o + 1], f.data[o + 2]))!;
      f.data[o] = r; f.data[o + 1] = g; f.data[o + 2] = b;
      f.data[o + 3] = 255; // binaire : opaque ou transparent, rien entre les deux
    }
  }

  return {
    before: before.size,
    after: new Set([...final.values()].map(hex)).size,
    adopted: [...new Set(adopted)].filter((h) => kept.includes(h)),
  };
}

type Retouche = {
  cheveux?: { teinte: number; saturationMax: number };
  vetement?: { de: [number, number]; teinte: number; saturationMax: number; pourquoi?: string };
};

function hsl(r: number, g: number, b: number): [number, number, number] {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
  if (!d) return [0, 0, l];
  const sat = d / (1 - Math.abs(2 * l - 1));
  let h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  h *= 60;
  return [h < 0 ? h + 360 : h, sat, l];
}

function fromHsl(h: number, s: number, l: number): RGB {
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x]
    : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [r, g, b].map((v) => Math.round((v + m) * 255)) as RGB;
}

/**
 * Reteint la chevelure sans toucher au reste.
 *
 * Le texte fait autorité sur l'apparence, et le rendu s'en écarte parfois. Deux
 * régénérations ont corrigé la couleur des cheveux de Wellan en perdant tout ce
 * qui faisait le personnage — le géant devenait frêle, l'armure disparaissait.
 * Un décalage de teinte, lui, ne change que ce qu'on vise.
 *
 * Encore faut-il viser juste. La couleur seule ne suffit pas : les mèches
 * partagent leurs bruns avec les cuirs du corps. La position seule ne suffit pas
 * non plus : la tête porte aussi la peau, les yeux, le haut de l'armure. Il faut
 * les deux — un ton chaud et sombre, situé dans la bande de la tête.
 *
 * La luminance est conservée telle quelle : c'est elle qui porte le modelé. Ce
 * qui était sombre le reste, et un décalage du rouge vers le jaune y devient
 * imperceptible — exactement le comportement d'une vraie chevelure blond foncé.
 */
function retoucher(frames: Frame[], r: Retouche): number {
  let touched = 0;

  /* Un vêtement se vise par sa teinte, sur toute la figure.
   *
   * Les cheveux se cherchent dans la bande de la tête parce qu'ils partagent
   * leurs bruns avec les cuirs. Une robe n'a pas ce problème : elle est la seule
   * chose de sa couleur sur le personnage, et elle descend jusqu'aux pieds. On
   * la prend donc par la teinte seule, dans une fenêtre déclarée — et l'on
   * garde la luminance, qui porte les plis.
   *
   * Ce que ça règle : Cull est sorti en robe ROUGE malgré une consigne qui
   * n'énumérait que des gris. Or le rouge appartient au sang, au feu et à
   * l'Empereur dans la palette du monde ; le Roi d'Argent en robe d'Empire est
   * un contresens que le contrôleur ne peut pas voir. Régénérer aurait risqué
   * la couronne et la fourrure, obtenues au deuxième essai seulement. */
  if (r.vetement) {
    const { de, teinte, saturationMax } = r.vetement;
    for (const f of frames) {
      for (let i = 0; i < f.width * f.height; i++) {
        const o = i * f.channels;
        if (f.data[o + 3] < 16) continue;
        const [h, sat, l] = hsl(f.data[o], f.data[o + 1], f.data[o + 2]);
        // Une teinte trop pâle n'a pas d'identité à déplacer : la déplacer
        // retournerait un neutre, ce qui a déjà noirci un manteau une fois.
        if (sat <= 0.22) continue;
        /* La carnation ne se reteint jamais, quelle que soit la fenêtre
         * déclarée. Le premier essai visait les rouges de la robe de Cull en
         * [340, 20] : les ombres de la peau vivent à 20-30 degrés, et le roi
         * est ressorti le visage et les mains gris. C'est la faute que le
         * contrôleur mécanique ne peut pas voir — il mesure la palette et la
         * géométrie, jamais un visage. Une consigne mal bornée ne doit pas
         * pouvoir la produire, donc la garde est ici et non dans le fichier. */
        if (h >= 14 && h <= 44 && l >= 0.30) continue;
        const dedans = de[0] <= de[1] ? h >= de[0] && h <= de[1] : h >= de[0] || h <= de[1];
        if (!dedans) continue;
        const [nr, ng, nb] = fromHsl(teinte, Math.min(sat, saturationMax), l);
        f.data[o] = nr; f.data[o + 1] = ng; f.data[o + 2] = nb;
        touched++;
      }
    }
  }

  if (!r.cheveux) return touched;
  const { teinte, saturationMax } = r.cheveux;

  for (const f of frames) {
    let top = f.height;
    for (let y = 0; y < f.height && top === f.height; y++) {
      for (let x = 0; x < f.width; x++) if (f.data[(y * f.width + x) * f.channels + 3] >= 16) { top = y; break; }
    }

    for (let y = top; y < Math.min(top + 13, f.height); y++) {
      for (let x = 0; x < f.width; x++) {
        const o = (y * f.width + x) * f.channels;
        if (f.data[o + 3] < 16) continue;
        const [h, sat, l] = hsl(f.data[o], f.data[o + 1], f.data[o + 2]);
        // Chaud et sombre : la chevelure. La peau est plus claire, l'or plus
        // jaune, le contour et l'armure trop peu saturés pour entrer ici.
        if (h >= 32 || sat <= 0.25 || l > 0.58) continue;
        const [nr, ng, nb] = fromHsl(teinte, Math.min(sat * 0.75, saturationMax), l);
        f.data[o] = nr; f.data[o + 1] = ng; f.data[o + 2] = nb;
        touched++;
      }
    }
  }
  return touched;
}

/** Les PNG d'un dossier, sous-dossiers compris. */
function pngs(dir: string): string[] {
  const out: string[] = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith(".")) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...pngs(full));
    else if (e.name.toLowerCase().endsWith(".png")) out.push(full);
  }
  return out;
}

/**
 * Rang d'un état dans le cycle.
 *
 * Le repos ouvre la marche, toujours. Se fier au tri alphabétique des dossiers
 * marcherait aujourd'hui — « Idle » précède « walk » par accident de casse — et
 * casserait le jour où un export livrera « Walk » et « idle ». On nomme donc ce
 * qu'on attend au lieu de le laisser au hasard de l'ASCII.
 */
function stateRank(state: string): number {
  const s = state.toLowerCase();
  if (/idle|repos|stand|immobile/.test(s)) return 0;
  if (/walk|marche|run|course/.test(s)) return 1;
  return 2;
}

/**
 * Range les images par direction, chaque direction ordonnée par état.
 *
 * On ne devine pas le schéma d'export : on lit les chemins. Un outil qui
 * livrera demain quatre images de marche par direction tombera dans le même
 * classement sans qu'il faille toucher à ce code.
 */
function byDirection(files: string[], root: string): Map<string, string[]> {
  type Item = { file: string; state: string; animation: boolean };
  const groups = new Map<string, Item[]>();

  for (const f of files) {
    const rel = path.relative(root, f);
    const parts = rel.split(path.sep);
    const animation = parts.includes("animations");

    /*
     * Une pose de rotation porte sa direction dans le nom du fichier ; une image
     * d'animation la porte dans le chemin, et s'appelle « frame_000.png ». On
     * cherche donc dans le dossier pour les secondes, dans le nom pour les
     * premières — sans quoi la moitié du rendu resterait invisible.
     */
    const hay = animation ? parts.slice(0, -1).join("/").toLowerCase() : path.basename(f).toLowerCase();
    const dir = DIRECTIONS.find((d) => hay.includes(d));
    if (!dir) continue;

    groups.set(dir, [...(groups.get(dir) ?? []), { file: f, state: parts[0] ?? "", animation }]);
  }

  const out = new Map<string, string[]>();
  for (const [dir, list] of groups) {
    /*
     * Une vraie animation prime sur des poses juxtaposées : elle a été calculée
     * comme un mouvement continu, là où deux états séparés ne sont que deux
     * dessins qu'on fait alterner.
     */
    const anim = list.filter((x) => x.animation).sort((a, b) => a.file.localeCompare(b.file));
    if (anim.length >= 2) { out.set(dir, cycle(anim.map((x) => x.file))); continue; }

    list.sort((a, b) => stateRank(a.state) - stateRank(b.state) || a.file.localeCompare(b.file));
    out.set(dir, list.map((x) => x.file));
  }
  return out;
}

/**
 * Réduit une animation aux quatre images d'une colonne de planche.
 *
 * L'API garde la pose de repos en tête puis boucle : la dernière image revient
 * sur la première. La conserver ferait battre le cycle deux fois au même
 * endroit. On l'écarte, puis on échantillonne régulièrement ce qui reste — ce
 * qui vaut pour cinq images comme pour seize.
 */
function cycle(frames: string[]): string[] {
  const usable = frames.length > COLS ? frames.slice(0, -1) : frames;
  if (usable.length <= COLS) return usable;
  return Array.from({ length: COLS }, (_, i) => usable[Math.round((i * usable.length) / COLS)]);
}

/** Nom des états traversés, dans l'ordre du cycle. */
function statesOf(files: string[], root: string): string[] {
  const anim = new Set<string>();
  for (const f of files) {
    const parts = path.relative(root, f).split(path.sep);
    const i = parts.indexOf("animations");
    if (i >= 0 && parts[i + 1]) anim.add(parts[i + 1]);
  }
  if (anim.size) return [...anim].sort();

  const seen = new Map<string, number>();
  for (const f of files) {
    const st = path.relative(root, f).split(path.sep)[0] ?? "";
    if (st && !seen.has(st)) seen.set(st, stateRank(st));
  }
  return [...seen.entries()].sort((a, b) => a[1] - b[1]).map(([s]) => s);
}

/**
 * Écart de ligne de sol entre les images d'une même rangée.
 *
 * Un cycle de marche fait varier la silhouette — l'enjambée descend d'un pixel
 * ou deux, c'est la marche elle-même. Au-delà, ce n'est plus une foulée mais un
 * personnage mal calé, qui sautera à chaque pas dans le moteur.
 */
function baselineSpread(frames: Frame[]): number {
  const bottoms = frames.map((f) => {
    for (let y = f.height - 1; y >= 0; y--)
      for (let x = 0; x < f.width; x++)
        if (f.data[(y * f.width + x) * f.channels + 3] >= 16) return y;
    return -1;
  });
  return Math.max(...bottoms) - Math.min(...bottoms);
}

async function build(id: string, palette: RGB[]): Promise<boolean> {
  const dir = path.join(SOURCES, id);
  const files = pngs(dir);
  debordements = [];
  const groups = byDirection(files, dir);
  const states = statesOf(files, dir);

  const missing = ROWS.filter((r) => !groups.has(r));
  if (missing.length) {
    console.log(`${C.red}✗${C.off} ${id} — direction(s) absente(s) : ${missing.join(", ")}`);
    return false;
  }

  // Quatre colonnes par rangée. Un état de repos seul les remplit toutes les
  // quatre : le sprite ne s'anime pas encore, mais il entre dans le moteur.
  const chosen: string[][] = ROWS.map((r) => {
    const f = groups.get(r)!;
    return Array.from({ length: COLS }, (_, i) => f[i % f.length]);
  });

  const frames: Frame[] = [];
  for (const row of chosen) for (const f of row) frames.push(await readPng(f));

  const retoucheFile = path.join(SOURCES, `${id}.retouche.json`);
  let retouched = 0;
  if (fs.existsSync(retoucheFile)) {
    retouched = retoucher(frames, JSON.parse(fs.readFileSync(retoucheFile, "utf8")) as Retouche);
  }

  const stat = snap(frames, palette);

  const W = SPRITE * COLS, H = SPRITE * ROWS.length;
  const sheet = Buffer.alloc(W * H * 4, 0);
  frames.forEach((f, n) => {
    const ox = (n % COLS) * SPRITE, oy = Math.floor(n / COLS) * SPRITE;
    for (let y = 0; y < SPRITE; y++) for (let x = 0; x < SPRITE; x++) {
      const s = (y * SPRITE + x) * f.channels, d = ((oy + y) * W + ox + x) * 4;
      sheet[d] = f.data[s]; sheet[d + 1] = f.data[s + 1];
      sheet[d + 2] = f.data[s + 2]; sheet[d + 3] = f.data[s + 3];
    }
  });

  fs.mkdirSync(OUT, { recursive: true });
  const dest = path.join(OUT, `${id}.png`);
  await sharp(sheet, { raw: { width: W, height: H, channels: 4 } }).png({ compressionLevel: 9 }).toFile(dest);

  const frameCount = groups.get("south")!.length;
  const spread = Math.max(...ROWS.map((_, r) => baselineSpread(frames.slice(r * COLS, (r + 1) * COLS))));
  console.log(`${C.green}✓${C.off} ${id} → ${path.relative(ROOT, dest)}  ${W}×${H}`);
  console.log(`  ${C.dim}palette ${stat.before} → ${stat.after} teintes${C.off}`);
  if (retouched) console.log(`  ${C.dim}retouche : ${retouched} pixels de chevelure reteints${C.off}`);
  if (stat.adopted.length) {
    console.log(`  ${C.yellow}${stat.adopted.length} teinte(s) sans équivalent dans CONTEXTE.md, conservées :${C.off}`);
    console.log(`  ${C.dim}${stat.adopted.join(" ")}${C.off}`);
    console.log(`  ${C.dim}→ les ajouter à la palette du monde si elles doivent servir aux autres personnages${C.off}`);
  }
  for (let i = 0; i < ROWS.length; i++) {
    console.log(`  ${C.dim}rangée ${i + 1} ${ROW_LABEL[ROWS[i]].padEnd(14)} ${ROWS[i]}${C.off}`);
  }
  if (debordements.length) {
    const pire = debordements.sort((a, b) => Number(b.split("×")[1]) - Number(a.split("×")[1]))[0];
    console.log(`  ${C.red}${debordements.length} image(s) plus grandes que la cellule de ${SPRITE} px — jusqu'à ${pire}${C.off}`);
    console.log(`  ${C.dim}le personnage est rogné : régénérer avec une taille plus petite${C.off}`);
  }
  console.log(`  ${C.dim}cycle ${states.join(" → ")}${states.length < COLS ? ", répété" : ""} sur ${COLS} colonnes${C.off}`);
  if (frameCount < 2) {
    console.log(`  ${C.yellow}une seule pose : les 4 colonnes la répètent — le sprite ne marche pas encore${C.off}`);
  }
  if (spread > 2) {
    console.log(`  ${C.yellow}ligne de sol variable de ${spread} px dans une rangée — le sprite sautera à chaque pas${C.off}`);
  }
  return true;
}

/**
 * Assemble un jeu de tuiles de Wang pour Godot.
 *
 * Le service rend seize tuiles couvrant toutes les combinaisons de coins entre
 * deux terrains, plus les métadonnées qui disent lesquelles. C'est ce qui permet
 * à un tapis de s'arrêter proprement sur la pierre, quelle que soit sa forme.
 *
 * La planche les range par signature de coins — NO, NE, SO, SE lus comme un
 * nombre binaire — pour que le moteur trouve la bonne tuile par calcul plutôt
 * que par table.
 */
async function buildTileset(id: string, palette: RGB[]): Promise<boolean> {
  const dir = path.join(SOURCES, `${id}-tuiles`);
  const meta = path.join(dir, "reponse.json");
  if (!fs.existsSync(meta)) {
    console.log(`${C.red}✗${C.off} ${id} — reponse.json absent de ${path.relative(ROOT, dir)}/`);
    return false;
  }

  const r = JSON.parse(fs.readFileSync(meta, "utf8"));
  const tiles: { corners: Record<string, string> }[] = r.tileset?.tiles ?? [];
  const size: number = r.tileset?.tile_size?.width ?? TUILE;

  /*
   * La signature de coins se déduit de l'image, non des métadonnées.
   *
   * Le service les a déjà rendues fausses deux fois : une planche où « lower »
   * et « upper » désignaient l'inverse de ce que montraient les images, et une
   * tuile déclarée uniforme qui portait une bordure. Assemblée sur la foi de
   * ces étiquettes, la salle sortait à l'envers et le liseré doré flottait à
   * côté de la frontière.
   *
   * Or la réponse est dans le fichier : il suffit de regarder ce que chaque
   * coin montre. On échantillonne un carré à chacun des quatre angles et on
   * sépare les deux terrains par regroupement, sans rien présumer de leur
   * couleur.
   */
  const brut: Frame[] = [];
  for (let i = 0; i < tiles.length; i++) {
    const f = path.join(dir, `tileset-tiles-${i}-image.png`);
    if (fs.existsSync(f)) brut.push(await readTile(f));
  }

  /**
   * Teinte moyenne d'un quadrant, l'or du liseré exclu.
   *
   * La bordure de transition n'appartient à aucun des deux terrains ; la compter
   * fait basculer du mauvais côté tout quadrant qu'elle traverse — et ce sont
   * précisément les tuiles qui portent l'information.
   */
  const moyenne = (f: Frame, x0: number, y0: number, n: number): RGB | null => {
    let r = 0, g = 0, b = 0, vus = 0;
    for (let y = y0; y < y0 + n; y++) for (let x = x0; x < x0 + n; x++) {
      const o = (y * f.width + x) * f.channels;
      if (f.data[o + 3] < 16) continue;
      const [pr, pg, pb] = [f.data[o], f.data[o + 1], f.data[o + 2]];
      if (pr > 120 && pg > 90 && pb < 90 && pr > pb + 50) continue; // liseré doré
      r += pr; g += pg; b += pb; vus++;
    }
    return vus ? [r / vus, g / vus, b / vus] : null;
  };

  /*
   * Les deux terrains se découvrent, ils ne se décrivent pas.
   *
   * Le premier jet cherchait « du vert contre du gris » — vrai pour un tapis
   * d'émeraude sur du dallage, faux dès la première lande côtière, où l'herbe
   * et la pierre claire sont toutes deux à leur manière du vert-gris. Aucune
   * signature n'était alors reconnue et le jeu paraissait vide.
   *
   * On échantillonne donc les quatre quadrants des seize tuiles, et l'on sépare
   * ces soixante-quatre points en deux groupes par leur seule distance
   * perceptuelle. Le procédé ne sait rien des terrains qu'il sépare, ce qui est
   * exactement la raison pour laquelle il marche sur tous.
   */
  const q = Math.max(2, Math.floor(size / 2));
  const coins: { tuile: number; place: number; lab: RGB }[] = [];
  for (const [i, f] of brut.entries()) {
    const places: [number, number][] = [[0, 0], [size - q, 0], [0, size - q], [size - q, size - q]];
    places.forEach(([x, y], place) => {
      const m = moyenne(f, x, y, q);
      if (m) coins.push({ tuile: i, place, lab: oklab(m) });
    });
  }

  // Deux germes : les deux échantillons les plus éloignés l'un de l'autre.
  let a = 0, z = 0, ecart = -1;
  for (let i = 0; i < coins.length; i++) {
    for (let j = i + 1; j < coins.length; j++) {
      const d = Math.hypot(coins[i].lab[0] - coins[j].lab[0], coins[i].lab[1] - coins[j].lab[1], coins[i].lab[2] - coins[j].lab[2]);
      if (d > ecart) { ecart = d; a = i; z = j; }
    }
  }
  let centres: RGB[] = [coins[a].lab, coins[z].lab];
  const proche = (p: RGB) =>
    Math.hypot(centres[0][0] - p[0], centres[0][1] - p[1], centres[0][2] - p[2])
      <= Math.hypot(centres[1][0] - p[0], centres[1][1] - p[1], centres[1][2] - p[2]) ? 0 : 1;

  for (let tour = 0; tour < 12; tour++) {
    const somme: RGB[] = [[0, 0, 0], [0, 0, 0]];
    const compte = [0, 0];
    for (const c of coins) {
      const k = proche(c.lab);
      somme[k][0] += c.lab[0]; somme[k][1] += c.lab[1]; somme[k][2] += c.lab[2];
      compte[k]++;
    }
    centres = centres.map((c, k) => compte[k] ? [somme[k][0] / compte[k], somme[k][1] / compte[k], somme[k][2] / compte[k]] as RGB : c);
  }

  // Le plus sombre porte le numéro zéro : convention arbitraire, mais stable
  // d'un jeu de tuiles à l'autre, ce qui est tout ce qu'on lui demande.
  const inverser = centres[0][0] > centres[1][0];

  const read = new Map<number, Frame>();
  let desaccords = 0;
  for (const [i, f] of brut.entries()) {
    let sig = 0;
    for (let place = 0; place < 4; place++) {
      const c = coins.find((x) => x.tuile === i && x.place === place);
      let k = c ? proche(c.lab) : 0;
      if (inverser) k = 1 - k;
      sig = (sig << 1) | k;
    }
    const t = tiles[i]?.corners;
    if (t) {
      const annonce = ["NW", "NE", "SW", "SE"].reduce((n, cc) => (n << 1) | (t[cc] === "upper" ? 1 : 0), 0);
      if (annonce !== sig && annonce !== (~sig & 15)) desaccords++;
    }
    if (!read.has(sig)) read.set(sig, f);
  }

  const missing = [...Array(16).keys()].filter((n) => !read.has(n));
  if (missing.length) {
    console.log(`${C.red}✗${C.off} ${id} — ${missing.length} combinaison(s) de coins introuvable(s) dans les images`);
    console.log(`  ${C.dim}manquantes : ${missing.map((n) => n.toString(2).padStart(4, "0")).join(" ")}${C.off}`);
    return false;
  }

  const frames = [...Array(16).keys()].map((n) => read.get(n)!);
  const stat = snap(frames, palette);

  /** La teinte moyenne d'un terrain, pour que le manifeste dise lequel est lequel. */
  const couleurDe = (n: number) => {
    const m = moyenne(frames[n], 0, 0, size);
    return m ? `#${m.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("")}` : "—";
  };

  const W = size * 16;
  const sheet = Buffer.alloc(W * size * 4, 0);
  frames.forEach((f, n) => {
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const si = (y * f.width + x) * f.channels, di = (y * W + n * size + x) * 4;
      sheet[di] = f.data[si]; sheet[di + 1] = f.data[si + 1];
      sheet[di + 2] = f.data[si + 2]; sheet[di + 3] = f.data[si + 3];
    }
  });

  fs.mkdirSync(LIEUX, { recursive: true });
  await sharp(sheet, { raw: { width: W, height: size, channels: 4 } })
    .png({ compressionLevel: 9 }).toFile(path.join(LIEUX, `${id}.png`));

  const prompts = r.metadata?.terrain_prompts ?? {};
  fs.writeFileSync(path.join(LIEUX, `${id}.json`), JSON.stringify({
    tuile: size,
    colonnes: 16,
    ordre: "signature des coins, NO NE SO SE lus en binaire — colonne = NO*8 + NE*4 + SO*2 + SE",
    terrain0: { couleur: couleurDe(0) },
    terrain1: { couleur: couleurDe(15) },
    decrits: { lower: String(prompts.lower ?? ""), upper: String(prompts.upper ?? "") },
    note: "Les deux terrains sont séparés par regroupement des couleurs des images, non lus dans les étiquettes : le service les a déjà rendues permutées. « decrits » rappelle ce qui a été demandé, sans garantir l'ordre.",
  }, null, 2) + "\n");

  console.log(`${C.green}✓${C.off} ${id} → ${path.relative(ROOT, path.join(LIEUX, `${id}.png`))}  ${W}×${size}`);
  console.log(`  ${C.dim}16 tuiles de Wang, palette ${stat.before} → ${stat.after} teintes${C.off}`);
  if (desaccords) {
    console.log(`  ${C.yellow}${desaccords} tuile(s) dont les coins annoncés ne correspondent pas à l'image — signature relue sur les pixels${C.off}`);
  }
  return true;
}

/** Une tuile se lit telle quelle : pas de recadrage, elle est déjà à sa taille. */
async function readTile(file: string): Promise<Frame> {
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return { data, width: info.width, height: info.height, channels: info.channels };
}

async function main() {
  if (!fs.existsSync(SOURCES)) {
    console.log(`Rien dans ${path.relative(ROOT, SOURCES)}/. Y déposer les rendus bruts de l'IA graphique.`);
    return;
  }

  const asked = process.argv.slice(2).filter((a) => !a.startsWith("-"));
  const ids = asked.length
    ? asked
    : fs.readdirSync(SOURCES, { withFileTypes: true }).filter((e) => e.isDirectory() && !e.name.startsWith(".")).map((e) => e.name);

  if (!ids.length) {
    console.log(`Rien dans ${path.relative(ROOT, SOURCES)}/.`);
    return;
  }

  const palette = worldPalette();
  console.log(`Palette du monde : ${palette.length} teintes lues dans CONTEXTE.md\n`);

  let ok = 0;
  for (const id of ids) {
    const tuiles = id.endsWith("-tuiles");
    const nom = tuiles ? id.slice(0, -"-tuiles".length) : id;
    if (!fs.existsSync(path.join(SOURCES, id))) { console.log(`${C.red}✗${C.off} ${id} — absent de sources/`); continue; }
    if (tuiles ? await buildTileset(nom, palette) : await build(id, palette)) ok++;
  }
  console.log(`\n${ok}/${ids.length} planche(s) assemblée(s). Contrôle : npm run art:verifier`);
  process.exitCode = ok === ids.length ? 0 : 1;
}

main();
