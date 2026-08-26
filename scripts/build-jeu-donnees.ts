/**
 * La passerelle entre le Codex et le jeu.
 *
 * Le Codex sait qui est Wellan, où se dresse le Château, qui est lié à qui. Le
 * jeu, lui, n'a pas à relire 511 fiches ni à connaître le format de l'Oracle :
 * il lui faut un fichier plat, petit, et présent après un simple `git pull`.
 *
 * C'est le point : `data/` n'est pas versionné — l'index contient le texte
 * intégral des romans. Le produit de ce script, lui, l'est, parce qu'il ne
 * retient que ce que l'Oracle a écrit lui-même : noms, rôles d'une phrase,
 * tomes de présence, liens. Aucune prose des romans n'y entre.
 *
 * Usage :
 *   npm run jeu:donnees
 */
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";
import { loadCodex } from "../lib/codex.ts";

const ROOT = path.resolve(import.meta.dirname, "..");
const SORTIE = path.join(ROOT, "jeu", "godot", "donnees");
const ART = path.join(ROOT, "jeu", "art");

const C = { red: "\x1b[31m", yellow: "\x1b[33m", green: "\x1b[32m", dim: "\x1b[2m", off: "\x1b[0m" };

/** Au plus quatre liens par personnage : de quoi nourrir un dialogue, pas une encyclopédie. */
const LIENS_MAX = 4;

/**
 * Teintes d'attente, prises dans la palette du monde.
 *
 * Un personnage sans planche n'est pas absent du jeu : il y paraît en
 * silhouette, colorée d'après son identifiant. On le voit, on lui parle, et le
 * jour où son sprite arrive, seule l'image change. Faire attendre le contenu que
 * l'art soit prêt reviendrait à ne jamais avancer.
 */
const TEINTES = ["#1C7A4E", "#2D5FA8", "#A76BC4", "#C08F34", "#8B2020", "#736C82", "#43C47F", "#7A5223"];

function teinteDe(id: string): string {
  let n = 0;
  for (const c of id) n = (n * 31 + c.charCodeAt(0)) >>> 0;
  return TEINTES[n % TEINTES.length];
}

/**
 * Dessine la silhouette d'attente.
 *
 * Une figure encapuchonnée de 32×32, en quatre directions et quatre images —
 * exactement la disposition d'une vraie planche, pour que le moteur n'ait pas à
 * distinguer les deux cas. Le corps est peint en blanc afin que Godot puisse le
 * teinter par `modulate` ; le contour reste noir et ne bouge pas.
 */
async function silhouette(fichier: string) {
  const S = 32, L = S * 4, H = S * 4;
  const buf = Buffer.alloc(L * H * 4, 0);

  const point = (x: number, y: number, blanc: boolean) => {
    if (x < 0 || y < 0 || x >= L || y >= H) return;
    const o = (y * L + x) * 4;
    buf[o] = blanc ? 255 : 11; buf[o + 1] = blanc ? 255 : 10;
    buf[o + 2] = blanc ? 255 : 16; buf[o + 3] = 255;
  };

  for (let rangee = 0; rangee < 4; rangee++) {
    for (let colonne = 0; colonne < 4; colonne++) {
      const ox = colonne * S, oy = rangee * S;
      // Le balancement de la marche : deux images sur quatre penchent d'un pixel.
      const pas = colonne === 1 ? 1 : colonne === 3 ? -1 : 0;

      for (let y = 5; y <= 29; y++) {
        // La cape s'évase vers le bas ; la tête est plus étroite.
        const demi = y < 13 ? 4 : Math.min(6 + Math.floor((y - 13) / 3), 9);
        const centre = 16 + (y > 20 ? pas : 0);
        for (let x = centre - demi; x <= centre + demi; x++) {
          const bord = x === centre - demi || x === centre + demi || y === 5 || y === 29;
          point(ox + x, oy + y, !bord);
        }
      }
    }
  }
  await sharp(buf, { raw: { width: L, height: H, channels: 4 } }).png().toFile(fichier);
}

type Personnage = {
  nom: string;
  role: string;
  tomes: number[];
  planche: string | null;
  teinte: string;
  liens: { nom: string; nature: string }[];
};

type Lieu = { nom: string; role: string; tuiles: string | null };

function main() {
  const charge = loadCodex();
  if (!charge) {
    console.error("Codex absent. Lancez d'abord : npm run codex");
    process.exit(1);
  }
  const fiches = charge.codex.entries;

  fs.mkdirSync(SORTIE, { recursive: true });

  const personnages: Record<string, Personnage> = {};
  const lieux: Record<string, Lieu> = {};

  for (const f of fiches) {
    if (f.kind === "personnage") {
      const planche = path.join(ART, "personnages", `${f.id}.png`);
      personnages[f.id] = {
        nom: f.name,
        role: f.gloss,
        tomes: f.books ?? [],
        planche: fs.existsSync(planche) ? `${f.id}.png` : null,
        teinte: teinteDe(f.id),
        liens: (f.relations ?? []).slice(0, LIENS_MAX).map((r) => ({ nom: r.name, nature: r.nature })),
      };
    } else if (f.kind === "lieu") {
      const tuiles = path.join(ART, "lieux", `${f.id}.png`);
      lieux[f.id] = {
        nom: f.name,
        role: f.gloss,
        tuiles: fs.existsSync(tuiles) ? `${f.id}.png` : null,
      };
    }
  }

  const monde = {
    version: 1,
    batiLe: new Date().toISOString().slice(0, 10),
    provenance: "Fiches du Codex — résumés produits par l'Oracle. Aucune phrase des romans.",
    personnages,
    lieux,
  };

  const fichier = path.join(SORTIE, "monde.json");
  fs.writeFileSync(fichier, JSON.stringify(monde, null, 1) + "\n");

  const avecPlanche = Object.values(personnages).filter((p) => p.planche).length;
  const avecTuiles = Object.values(lieux).filter((l) => l.tuiles).length;
  const poids = (fs.statSync(fichier).size / 1024).toFixed(0);

  console.log(`${C.green}✓${C.off} ${path.relative(ROOT, fichier)}  ${poids} Ko`);
  console.log(`  ${C.dim}${Object.keys(personnages).length} personnages, dont ${avecPlanche} avec planche${C.off}`);
  console.log(`  ${C.dim}${Object.keys(lieux).length} lieux, dont ${avecTuiles} avec tuiles${C.off}`);

  /* Les salles sont écrites à la main : ce sont des décisions de mise en scène,
   * pas des données à déduire. Le script se contente de les valider. */
  const salles = path.join(SORTIE, "salles");
  let fautes = 0;
  for (const f of fs.existsSync(salles) ? fs.readdirSync(salles) : []) {
    if (!f.endsWith(".json")) continue;
    const salle = JSON.parse(fs.readFileSync(path.join(salles, f), "utf8"));
    for (const p of salle.personnages ?? []) {
      if (!personnages[p.fiche]) {
        console.log(`  ${C.red}${f} : fiche inconnue « ${p.fiche} »${C.off}`);
        fautes++;
      }
    }
    if (salle.lieu && !lieux[salle.lieu]) {
      console.log(`  ${C.red}${f} : lieu inconnu « ${salle.lieu} »${C.off}`);
      fautes++;
    }
    const noms = (salle.personnages ?? []).map((p: { fiche: string }) => personnages[p.fiche]?.nom ?? "?");
    console.log(`  ${C.dim}${f} → ${salle.taille?.[0]}×${salle.taille?.[1]} tuiles${noms.length ? `, ${noms.join(", ")}` : ""}${C.off}`);
  }

  silhouette(path.join(SORTIE, "silhouette.png")).then(() => {
    console.log(`  ${C.dim}silhouette d'attente écrite${C.off}`);
    if (fautes) process.exitCode = 1;
  });
}

main();
