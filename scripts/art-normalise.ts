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

const SPRITE = 32;
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
  return { data, width: info.width, height: info.height, channels: info.channels };
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

  const kept = [...share.entries()].sort((a, b) => b[1] - a[1]).slice(0, MAX_COLORS).map(([h]) => h);
  const keptRgb: RGB[] = kept.map((h) => [
    parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16),
  ]);
  const keptLab = keptRgb.map(oklab);
  const final = new Map<number, RGB>();
  for (const [k, rgb] of map) {
    final.set(k, kept.includes(hex(rgb)) ? rgb : keptRgb[nearest(rgb, keptRgb, keptLab)]);
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
 * Range les images par direction.
 *
 * On ne devine pas le schéma d'export : on lit le nom des fichiers. Un outil
 * qui livrera demain quatre images de marche par direction tombera dans le même
 * classement sans qu'il faille toucher à ce code.
 */
function byDirection(files: string[]): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (const f of files.sort()) {
    const base = path.basename(f).toLowerCase();
    const dir = DIRECTIONS.find((d) => base.includes(d));
    if (!dir) continue;
    groups.set(dir, [...(groups.get(dir) ?? []), f]);
  }
  return groups;
}

async function build(id: string, palette: RGB[]): Promise<boolean> {
  const dir = path.join(SOURCES, id);
  const groups = byDirection(pngs(dir));

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

  const odd = frames.find((f) => f.width !== SPRITE || f.height !== SPRITE);
  if (odd) {
    console.log(`${C.red}✗${C.off} ${id} — une image fait ${odd.width}×${odd.height}, attendu ${SPRITE}×${SPRITE}`);
    return false;
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
  console.log(`${C.green}✓${C.off} ${id} → ${path.relative(ROOT, dest)}  ${W}×${H}`);
  console.log(`  ${C.dim}palette ${stat.before} → ${stat.after} teintes${C.off}`);
  if (stat.adopted.length) {
    console.log(`  ${C.yellow}${stat.adopted.length} teinte(s) sans équivalent dans CONTEXTE.md, conservées :${C.off}`);
    console.log(`  ${C.dim}${stat.adopted.join(" ")}${C.off}`);
    console.log(`  ${C.dim}→ les ajouter à la palette du monde si elles doivent servir aux autres personnages${C.off}`);
  }
  for (let i = 0; i < ROWS.length; i++) {
    console.log(`  ${C.dim}rangée ${i + 1} ${ROW_LABEL[ROWS[i]].padEnd(14)} ${ROWS[i]}${C.off}`);
  }
  if (frameCount < COLS) {
    console.log(`  ${C.yellow}${frameCount} image(s) par direction : les 4 colonnes répètent le repos — le sprite ne marche pas encore${C.off}`);
  }
  return true;
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
    if (!fs.existsSync(path.join(SOURCES, id))) { console.log(`${C.red}✗${C.off} ${id} — absent de sources/`); continue; }
    if (await build(id, palette)) ok++;
  }
  console.log(`\n${ok}/${ids.length} planche(s) assemblée(s). Contrôle : npm run art:verifier`);
  process.exitCode = ok === ids.length ? 0 : 1;
}

main();
