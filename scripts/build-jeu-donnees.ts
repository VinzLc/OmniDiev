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

/**
 * Les effets de combat, dessinés plutôt que générés.
 *
 * Un arc d'épée et une boule de feu sont des formes exactes : un rayon, un
 * angle, une couleur par couronne. Le calcul les rend plus nets qu'un modèle,
 * les rend identiques à chaque fois, et ne coûte rien. On ne commande une image
 * que pour ce qu'on ne sait pas décrire en chiffres.
 */
async function effets(dossier: string) {
  const PAL = {
    blanc: [242, 242, 245], argent: [166, 168, 178], acier: [113, 114, 126],
    or: [240, 209, 116], ambre: [192, 143, 52], braise: [139, 32, 32], noir: [11, 10, 16],
  } as const;

  const toile = (l: number, h: number) => Buffer.alloc(l * h * 4, 0);
  const poser = (buf: Buffer, l: number, x: number, y: number, c: readonly number[]) => {
    if (x < 0 || y < 0 || x >= l) return;
    const o = (y * l + x) * 4;
    buf[o] = c[0]; buf[o + 1] = c[1]; buf[o + 2] = c[2]; buf[o + 3] = 255;
  };

  /* ── La taillade ──────────────────────────────────────────────────────
   * Trois images d'un arc qui descend, dessinées pointant vers l'est. Le
   * moteur les fait pivoter par quarts de tour : à 90 degrés une image de
   * pixel art tourne sans perdre un pixel, ce qui ne serait pas vrai d'un
   * angle quelconque.
   */
  const S = 32, pivot = { x: 4, y: 16 };
  /*
   * Un coup, non une auréole.
   *
   * Deux essais l'ont montré. Trop mince, l'arc passe pour un défaut
   * d'affichage. Trop large — cent soixante degrés au deuxième jet, presque un
   * demi-cercle d'un blanc épais — il cerne le personnage et se lit comme un
   * halo. Une lame balaie un quart de tour à peine, et près du corps.
   */
  const arcs = [
    { de: -58, a: -18, r0: 8, r1: 12 },
    { de: -26, a: 26, r0: 9, r1: 13 },
    { de: 18, a: 58, r0: 10, r1: 14 },
  ];
  const lame = toile(S * arcs.length, S);
  arcs.forEach((arc, n) => {
    for (let y = 0; y < S; y++) {
      for (let x = 0; x < S; x++) {
        const dx = x - pivot.x, dy = y - pivot.y;
        const r = Math.hypot(dx, dy);
        const a = (Math.atan2(dy, dx) * 180) / Math.PI;
        if (r < arc.r0 || r > arc.r1 || a < arc.de || a > arc.a) continue;
        /* Une seule ligne blanche au cœur, de l'acier autour : c'est le fil de
         * la lame qu'on voit, non une traînée de peinture. */
        const dedans = (r - arc.r0) / (arc.r1 - arc.r0);
        const c = dedans < 0.2 || dedans > 0.85 ? PAL.acier
          : dedans > 0.45 && dedans < 0.65 ? PAL.blanc : PAL.argent;
        poser(lame, S * arcs.length, n * S + x, y, c);
      }
    }
  });
  await sharp(lame, { raw: { width: S * arcs.length, height: S, channels: 4 } })
    .png().toFile(path.join(dossier, "taillade.png"));

  /* ── La boule de feu ──────────────────────────────────────────────────
   * Quatre images d'une braise qui bat. Le noyau reste, la couronne respire :
   * c'est ce battement qui distingue un feu d'un disque orange.
   */
  const F = 16, battements = [0, 0.6, 1, 0.6];
  const feu = toile(F * battements.length, F);
  battements.forEach((b, n) => {
    for (let y = 0; y < F; y++) {
      for (let x = 0; x < F; x++) {
        const r = Math.hypot(x - F / 2 + 0.5, y - F / 2 + 0.5);
        const enfle = 5.2 + b * 1.3;
        if (r > enfle) continue;
        const c = r < 1.8 ? PAL.blanc : r < 3.0 ? PAL.or : r < enfle - 1.2 ? PAL.ambre : PAL.braise;
        poser(feu, F * battements.length, n * F + x, y, c);
      }
    }
  });
  await sharp(feu, { raw: { width: F * battements.length, height: F, channels: 4 } })
    .png().toFile(path.join(dossier, "feu.png"));

  /* ── L'éclat ──────────────────────────────────────────────────────────
   * Trois images d'une couronne qui s'ouvre et s'amincit — ce qui reste
   * quand le feu a porté.
   */
  /*
   * Des rais qui partent du centre, non une couronne.
   *
   * Le premier jet évidait un anneau : cela donnait un beignet, pas une gerbe.
   * Une explosion se lit à ce qui s'en échappe, donc on trace huit branches
   * qui s'allongent et s'éloignent.
   */
  const rayons = [{ r0: 0, r1: 4 }, { r0: 2, r1: 6.5 }, { r0: 4.5, r1: 7.5 }];
  const eclat = toile(F * rayons.length, F);
  rayons.forEach((etape, n) => {
    const teinte = n === 0 ? PAL.blanc : n === 1 ? PAL.or : PAL.ambre;
    for (let branche = 0; branche < 8; branche++) {
      const a = (branche * Math.PI) / 4;
      for (let r = etape.r0; r <= etape.r1; r += 0.4) {
        const x = Math.round(F / 2 - 0.5 + Math.cos(a) * r);
        const y = Math.round(F / 2 - 0.5 + Math.sin(a) * r);
        poser(eclat, F * rayons.length, n * F + x, y, teinte);
        // Les branches s'épaississent près du centre, comme une flamme.
        if (r < etape.r0 + 1.5) {
          poser(eclat, F * rayons.length, n * F + x + 1, y, teinte);
          poser(eclat, F * rayons.length, n * F + x, y + 1, teinte);
        }
      }
    }
  });
  await sharp(eclat, { raw: { width: F * rayons.length, height: F, channels: 4 } })
    .png().toFile(path.join(dossier, "eclat.png"));

  return { taillade: arcs.length, feu: battements.length, eclat: rayons.length };
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

/**
 * Les peuples entrent aussi dans le monde.
 *
 * Ce qu'on affronte a un nom et une fiche au même titre que ce à quoi l'on
 * parle : les hommes-insectes ne sont pas un décor, ce sont des adversaires que
 * le Codex décrit — carapace, lances d'argent, sang toxique. Les laisser dehors
 * obligeait la scène à redire ce que la fiche disait déjà.
 */
type Peuple = { nom: string; role: string; planche: string | null };

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
  const peuples: Record<string, Peuple> = {};

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
    } else if (f.kind === "peuple") {
      const planche = path.join(ART, "personnages", `${f.id}.png`);
      peuples[f.id] = {
        nom: f.name,
        role: f.gloss,
        planche: fs.existsSync(planche) ? `${f.id}.png` : null,
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
    peuples,
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
  const peuplesArmes = Object.values(peuples).filter((p) => p.planche).length;
  console.log(`  ${C.dim}${Object.keys(peuples).length} peuples, dont ${peuplesArmes} avec planche${C.off}`);

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

  silhouette(path.join(SORTIE, "silhouette.png"))
    .then(() => effets(SORTIE))
    .then((n) => {
      console.log(`  ${C.dim}silhouette d'attente écrite${C.off}`);
      console.log(`  ${C.dim}effets dessinés : taillade ${n.taillade} images, feu ${n.feu}, éclat ${n.eclat}${C.off}`);
      if (fautes) process.exitCode = 1;
    });
}

main();
