/**
 * Contrôle les images rendues par l'IA graphique.
 *
 * La plupart des modèles produisent une image de 512 ou 1024 pixels où le
 * « pixel » est un effet de style : la grille n'est pas alignée, les bords sont
 * lissés, la palette compte des centaines de teintes. Une telle image paraît
 * juste à l'œil et se révèle inutilisable dans le moteur.
 *
 * Ces défauts sont mécaniques, donc mesurables. Ce script les mesure et dit quoi
 * corriger, plutôt que de laisser la découverte se faire dans Godot.
 *
 * Usage :
 *   npm run art:verifier                    tout jeu/art/
 *   npm run art:verifier -- jeu/art/personnages/wellan.png
 */
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";

const ROOT = path.resolve(import.meta.dirname, "..");
const ART = path.join(ROOT, "jeu", "art");

const SPRITE = 32;
const SHEET = { w: SPRITE * 4, h: SPRITE * 4 };
const TILE = 16;
const MAX_COLORS = 16;

const C = { red: "\x1b[31m", yellow: "\x1b[33m", green: "\x1b[32m", dim: "\x1b[2m", off: "\x1b[0m" };

type Finding = { level: "erreur" | "avis"; message: string; remede?: string };

type Pixels = { data: Buffer; width: number; height: number; channels: number };

/**
 * Facteur d'agrandissement réel de l'image.
 *
 * Une image « pixel art » sortie d'un modèle généraliste est presque toujours un
 * rendu haute résolution : ses pixels apparents sont des blocs uniformes de N×N.
 * Trouver ce N donne la vraie définition — et dit s'il suffit de réduire.
 */
function blockSize(px: Pixels, distinct: number): number {
  /*
   * Une image trop uniforme ne prouve rien : dans un aplat d'une seule teinte,
   * tout bloc est uniforme, et la détection conclurait à un agrandissement
   * imaginaire. Sous quatre couleurs, on s'abstient.
   */
  if (distinct < 4) return 1;

  const { data, width, height, channels } = px;
  const at = (x: number, y: number) => {
    const i = (y * width + x) * channels;
    return `${data[i]},${data[i + 1]},${data[i + 2]},${channels > 3 ? data[i + 3] : 255}`;
  };

  const uniform = (n: number) => {
    if (width % n || height % n) return false;
    for (let by = 0; by < height; by += n) {
      for (let bx = 0; bx < width; bx += n) {
        const ref = at(bx, by);
        for (let y = by; y < by + n; y++) {
          for (let x = bx; x < bx + n; x++) if (at(x, y) !== ref) return false;
        }
      }
    }
    return true;
  };

  for (const n of [16, 12, 10, 8, 6, 5, 4, 3, 2]) if (uniform(n)) return n;
  return 1;
}

function palette({ data, width, height, channels }: Pixels) {
  const counts = new Map<string, number>();
  let transparent = 0;
  const total = width * height;

  for (let i = 0; i < total; i++) {
    const o = i * channels;
    const a = channels > 3 ? data[o + 3] : 255;
    if (a < 16) { transparent++; continue; }
    // Un alpha intermédiaire est un bord lissé : le pixel art n'en a pas.
    const key = `${data[o]},${data[o + 1]},${data[o + 2]}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }

  const opaque = total - transparent;
  // Une teinte présente sur moins d'un millième des pixels opaques ne construit
  // pas la forme : c'est un résidu de lissage ou de dégradé.
  const rare = [...counts.values()].filter((n) => n < Math.max(2, opaque / 1000)).length;

  return { colors: counts.size, rare, transparent, opaque, total };
}

function softEdges({ data, width, height, channels }: Pixels): number {
  if (channels < 4) return 0;
  let soft = 0;
  for (let i = 0; i < width * height; i++) {
    const a = data[i * channels + 3];
    if (a > 16 && a < 240) soft++;
  }
  return soft;
}

async function inspect(file: string): Promise<Finding[]> {
  const rel = path.relative(ROOT, file);
  const kind = rel.includes(`${path.sep}personnages${path.sep}`) ? "personnage" : "lieu";
  const out: Finding[] = [];

  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  {
      const px: Pixels = { data, width: info.width, height: info.height, channels: info.channels };
      const pal = palette(px);
      const block = blockSize(px, pal.colors);
      const soft = softEdges(px);

      // ── Définition ────────────────────────────────────────────────────
      if (block > 1) {
        out.push({
          level: "erreur",
          message: `image agrandie ${block}× — la définition réelle est ${px.width / block}×${px.height / block}`,
          remede: `réduire d'un facteur ${block} au plus proche voisin (jamais en interpolation lisse)`,
        });
      }

      const real = { w: px.width / block, h: px.height / block };
      if (kind === "personnage") {
        /*
         * Deux formes valides : la planche complète, ou une image isolée — un
         * outil qui génère les rotations une par une rend huit fichiers de
         * 32×32, et c'est aussi utilisable. Ce qui ne se négocie pas, c'est
         * que chaque côté tombe sur la grille.
         */
        if (real.w % SPRITE || real.h % SPRITE) {
          out.push({
            level: "erreur",
            message: `${real.w}×${real.h} — les deux côtés doivent être des multiples de ${SPRITE}`,
          });
        } else if (real.w !== SHEET.w || real.h !== SHEET.h) {
          out.push({
            level: "avis",
            message: `image isolée ${real.w}×${real.h} — à assembler en planche ${SHEET.w}×${SHEET.h} avant Godot`,
          });
        }
      } else if (real.w % TILE || real.h % TILE) {
        out.push({
          level: "erreur",
          message: `planche ${real.w}×${real.h} — les deux côtés doivent être des multiples de ${TILE}`,
        });
      }

      // ── Palette ───────────────────────────────────────────────────────
      if (pal.colors > MAX_COLORS) {
        out.push({
          level: pal.colors > MAX_COLORS * 4 ? "erreur" : "avis",
          message: `${pal.colors} couleurs — le style en admet ${MAX_COLORS}`,
          remede: "quantifier la palette, ou redemander l'image avec la contrainte explicite",
        });
      }

      /*
       * Des teintes résiduelles trahissent un lissage — mais seulement si les
       * bords en portent la trace. Une image aux pixels francs et à la grille
       * intacte, simplement riche en couleurs, relève de la dérive de palette,
       * qui se corrige sans regénérer. Ne pas confondre les deux : l'un est un
       * défaut de fabrication, l'autre un écart de consigne.
       */
      if (pal.rare > pal.colors / 3 && pal.colors > MAX_COLORS * 2) {
        out.push({
          level: soft || block > 1 ? "erreur" : "avis",
          message: `${pal.rare} teintes n'occupent presque aucun pixel`,
          remede: soft || block > 1
            ? "signature d'un lissage : exiger « aplats francs, aucun anti-aliasing » et regénérer"
            : "pixels francs par ailleurs — quantifier sur la palette du monde suffit",
        });
      }

      // ── Transparence ──────────────────────────────────────────────────
      if (soft > pal.total / 200) {
        out.push({
          level: "erreur",
          message: `${soft} pixels à transparence partielle — les bords sont lissés`,
          remede: "seuiller l'alpha : opaque ou transparent, rien entre les deux",
        });
      }

      if (!pal.transparent) {
        /*
         * Un personnage sans transparence est inutilisable : il traînerait son
         * fond sur le décor. Un sol, lui, couvre le terrain — il n'a rien à
         * détourer, et l'exiger serait une fausse alerte. La distinction ne
         * tient donc pas à l'image mais à ce qu'on en fait.
         */
        out.push({
          level: kind === "personnage" ? "erreur" : "avis",
          message: kind === "personnage"
            ? "aucun pixel transparent — le fond est plein"
            : "aucun pixel transparent — normal pour un sol, à corriger pour une tuile ajourée",
          remede: kind === "personnage" ? "détourer le fond, ou redemander avec fond transparent" : undefined,
        });
      }

  }
  return out;
}

/**
 * Les PNG sous `dir`, sous-dossiers compris.
 *
 * Un outil spécialisé ne rend pas un fichier : il rend une arborescence — un
 * dossier par état, un sous-dossier par jeu de rotations. Ne regarder que le
 * premier niveau revient à ne rien voir.
 */
function collect(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  const out: string[] = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith(".")) continue; // .DS_Store et consorts
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...collect(full));
    else if (e.name.toLowerCase().endsWith(".png")) out.push(full);
  }
  return out;
}

async function main() {
  const args = process.argv.slice(2).filter((a) => !a.startsWith("-"));
  let files: string[] = [];

  if (args.length) {
    files = args.map((a) => path.resolve(ROOT, a));
  } else {
    for (const sub of ["personnages", "lieux"]) files.push(...collect(path.join(ART, sub)));
  }
  files.sort();

  if (!files.length) {
    console.log(`Aucune image dans ${path.relative(ROOT, ART)}/personnages ou /lieux.`);
    console.log("Les commandes à jouer sont dans jeu/art/commandes/.");
    return;
  }

  let bad = 0;
  for (const file of files) {
    const rel = path.relative(ROOT, file);
    if (!fs.existsSync(file)) { console.log(`${C.red}✗${C.off} ${rel} — introuvable`); bad++; continue; }

    const findings = await inspect(file);
    const errors = findings.filter((f) => f.level === "erreur");

    if (!findings.length) {
      console.log(`${C.green}✓${C.off} ${rel}`);
      continue;
    }
    if (errors.length) bad++;

    console.log(`${errors.length ? C.red + "✗" : C.yellow + "!"}${C.off} ${rel}`);
    for (const f of findings) {
      console.log(`    ${f.level === "erreur" ? C.red : C.yellow}${f.message}${C.off}`);
      if (f.remede) console.log(`    ${C.dim}→ ${f.remede}${C.off}`);
    }
  }

  console.log(
    bad
      ? `\n${bad} image(s) à reprendre avant intégration.`
      : `\n${files.length} image(s) conformes.`,
  );
  process.exitCode = bad ? 1 : 0;
}

main();
