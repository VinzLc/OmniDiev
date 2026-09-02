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
import { ordered } from "../lib/codex-view.ts";
import { SONS, ecrireLesSons } from "../lib/sons.ts";
import { ecrireLesMusiques } from "../lib/musiques.ts";
import { loadLieuxAjoutes } from "../lib/corrections.ts";
import { GRILLE, CELLULE, LARGEUR, HAUTEUR, COULEURS, terrain, ESCALES } from "../lib/carte.ts";

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

/** Les humeurs déclinées d'un portrait, relevées sur les fichiers présents. */
function humeursDe(id: string): string[] {
  const dossier = path.join(ART, "portraits");
  if (!fs.existsSync(dossier)) return [];
  return fs.readdirSync(dossier)
    .filter((f) => f.startsWith(`${id}-`) && f.endsWith(".png"))
    .map((f) => f.slice(id.length + 1, -4))
    .sort();
}

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
    sangVif: [110, 26, 28], sangSombre: [61, 14, 16],
  } as const;

  const toile = (l: number, h: number) => Buffer.alloc(l * h * 4, 0);
  const poser = (buf: Buffer, l: number, x: number, y: number, c: readonly number[], h = Infinity) => {
    if (x < 0 || y < 0 || x >= l || y >= h) return;
    const o = (y * l + x) * 4;
    buf[o] = c[0]; buf[o + 1] = c[1]; buf[o + 2] = c[2]; buf[o + 3] = 255;
  };

  /* ── La taillade ──────────────────────────────────────────────────────
   * Trois images d'un arc qui descend, dessinées pointant vers l'est. Le
   * moteur les fait pivoter par quarts de tour : à 90 degrés une image de
   * pixel art tourne sans perdre un pixel, ce qui ne serait pas vrai d'un
   * angle quelconque.
   */
  /*
   * Soixante-quatre pixels de côté, le pivot à gauche.
   *
   * Ce n'est pas la largeur qui contraint mais la hauteur : au bout d'un arc
   * ouvert à soixante degrés, le rayon monte presque autant qu'il avance. Une
   * cellule de cinquante plafonnait la lame à vingt-huit pixels — moins que la
   * zone frappée d'origine. Il fallait donc grandir la toile pour allonger le
   * geste, non pousser les nombres dans celle qu'on avait.
   */
  const S = 64, pivot = { x: 8, y: 32 };
  /*
   * Un coup, non une auréole — mais un coup qui porte.
   *
   * Trois essais. Trop mince, l'arc passe pour un défaut d'affichage. Trop
   * large — cent soixante degrés au deuxième jet, presque un demi-cercle d'un
   * blanc épais — il cerne le personnage et se lit comme un halo. Resserré, il
   * ne portait plus qu'à quatorze pixels quand la zone frappée en couvrait
   * trente-sept : on touchait ce qu'on ne voyait pas atteindre, et le coup
   * paraissait court.
   *
   * Ce qui donne l'allonge est le rayon ; ce qui faisait l'auréole était
   * l'angle. On pousse donc le premier et l'on retient le second.
   *
   * Reste la forme du bandeau, et c'est elle qui a demandé le plus d'essais.
   * Épais et tiré de la main jusqu'au bout du geste, il remplit le coin et se
   * lit comme un bloc. Mince et d'épaisseur constante, il flotte loin du corps
   * comme une virgule détachée.
   *
   * Une taillade est effilée : large au milieu du geste, pincée aux deux bouts,
   * là où la lame entre et sort du champ. On fait donc varier l'épaisseur en
   * sinus le long de l'arc. Au centre la bande touche presque l'épaule, aux
   * extrémités elle s'efface — et c'est ce pincement, non le rayon seul, qui
   * fait lire un coup plutôt qu'un objet posé à côté du personnage.
   *
   * L'épaisseur se mesure vers l'intérieur autant que vers l'extérieur : un
   * premier réglage laissait huit pixels de vide entre l'épaule et le fer, et
   * la lame semblait flotter à côté du personnage plutôt que sortir de sa main.
   */
  const arcs = [
    { de: -55, a: -6, milieu: 24, epaisseur: 18 },
    { de: -30, a: 30, milieu: 26, epaisseur: 22 },
    { de: 6, a: 55, milieu: 25, epaisseur: 18 },
  ];
  const lame = toile(S * arcs.length, S);
  arcs.forEach((arc, n) => {
    for (let y = 0; y < S; y++) {
      for (let x = 0; x < S; x++) {
        const dx = x - pivot.x, dy = y - pivot.y;
        const r = Math.hypot(dx, dy);
        const a = (Math.atan2(dy, dx) * 180) / Math.PI;
        if (a < arc.de || a > arc.a) continue;

        // Position le long de l'arc, de 0 à 1 : l'épaisseur y suit un sinus.
        const t = (a - arc.de) / (arc.a - arc.de);
        const large = arc.epaisseur * Math.sin(Math.PI * t);
        const r0 = arc.milieu - large / 2, r1 = arc.milieu + large / 2;
        if (large < 1.2 || r < r0 || r > r1) continue;

        /* Une seule ligne blanche au cœur, de l'acier autour : c'est le fil de
         * la lame qu'on voit, non une traînée de peinture. */
        const dedans = (r - r0) / (r1 - r0);
        const c = dedans < 0.2 || dedans > 0.85 ? PAL.acier
          : dedans > 0.45 && dedans < 0.65 ? PAL.blanc : PAL.argent;
        poser(lame, S * arcs.length, n * S + x, y, c, S);
      }
    }
  });
  await sharp(lame, { raw: { width: S * arcs.length, height: S, channels: 4 } })
    .png().toFile(path.join(dossier, "taillade.png"));

  /* ── La boule de feu ──────────────────────────────────────────────────
   * Vingt-quatre pixels au lieu de seize, et trois couronnes au lieu de deux.
   *
   * La première était une pastille orange de six pixels de rayon : elle
   * traversait l'écran sans qu'on la voie partir, et le feu de Theandras
   * ressemblait à une étincelle. Un sort qui coûte un quart de l'énergie doit
   * se voir arriver.
   *
   * Le noyau reste blanc, la couronne bat, et une écharpe de braises la suit —
   * c'est ce qui donne la vitesse à l'œil, non la vitesse elle-même.
   */
  const F = 24, battements = [0, 0.5, 1, 0.5];
  const feu = toile(F * battements.length, F);
  battements.forEach((b, n) => {
    for (let y = 0; y < F; y++) {
      for (let x = 0; x < F; x++) {
        const dx = x - F / 2 + 0.5, dy = y - F / 2 + 0.5;
        const r = Math.hypot(dx, dy);
        const enfle = 8.4 + b * 1.6;

        // L'écharpe : une traîne vers l'arrière, plus étroite que la boule.
        const traine = dx < 0 && Math.abs(dy) < 2.6 - b * 0.6 && r < enfle + 3.5;
        if (r > enfle && !traine) continue;

        const c = r < 2.6 ? PAL.blanc
          : r < 4.6 ? PAL.or
          : r < enfle - 1.8 ? PAL.ambre
          : PAL.braise;
        poser(feu, F * battements.length, n * F + x, y, traine && r > enfle ? PAL.braise : c, F);
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
  const rayons = [{ r0: 0, r1: 6 }, { r0: 3, r1: 10 }, { r0: 6.5, r1: 12 }];
  const E = 32;
  const eclat = toile(E * rayons.length, E);
  rayons.forEach((etape, n) => {
    const teinte = n === 0 ? PAL.blanc : n === 1 ? PAL.or : PAL.ambre;
    for (let branche = 0; branche < 10; branche++) {
      const a = (branche * Math.PI) / 5;
      for (let r = etape.r0; r <= etape.r1; r += 0.35) {
        const x = Math.round(E / 2 - 0.5 + Math.cos(a) * r);
        const y = Math.round(E / 2 - 0.5 + Math.sin(a) * r);
        poser(eclat, E * rayons.length, n * E + x, y, teinte, E);
        // Les branches s'épaississent près du centre, comme une flamme.
        if (r < etape.r0 + 2.5) {
          poser(eclat, E * rayons.length, n * E + x + 1, y, teinte, E);
          poser(eclat, E * rayons.length, n * E + x, y + 1, teinte, E);
        }
      }
    }
  });
  await sharp(eclat, { raw: { width: E * rayons.length, height: E, channels: 4 } })
    .png().toFile(path.join(dossier, "eclat.png"));

  /* ── La mare de sang ──────────────────────────────────────────────────
   * Trois images d'une flaque qui s'élargit sous le corps. Une ellipse pure
   * ferait une tache de peinture ; on en déforme le rayon par une somme de
   * sinus, ce qui donne un contour irrégulier sans qu'on ait à le dessiner.
   */
  const M = 32, temps = [0.45, 0.75, 1.0];
  const sang = toile(M * temps.length, M);
  temps.forEach((t, n) => {
    for (let y = 0; y < M; y++) {
      for (let x = 0; x < M; x++) {
        /*
         * Un peu plus large que le corps, guère plus.
         *
         * Trop petite, elle disparaît sous lui et l'on ne voit rien. Trop
         * grande, elle monte derrière le corps et se lit comme une tenture
         * rouge accrochée au mur — ce qui est arrivé au deuxième réglage. Elle
         * doit déborder du corps de deux ou trois pixels, pas davantage, et
         * rester basse.
         */
        const dx = (x - M / 2 + 0.5) / 3.4;   // très aplatie : une flaque s'étale
        const dy = y - M / 2 + 0.5;
        const r = Math.hypot(dx, dy);
        const a = Math.atan2(dy, dx);
        const bord = (5.6 + 1.1 * Math.sin(a * 3 + 0.7) + 0.7 * Math.sin(a * 5 - 1.3)) * t;
        if (r > bord) continue;
        // Rouge au centre, cerné de plus sombre : l'inverse donnait un trou
        // noir bordé de rouge, qu'on lisait comme une fosse et non du sang.
        poser(sang, M * temps.length, n * M + x, y, r > bord - 1.8 ? PAL.sangSombre : PAL.sangVif, M);
      }
    }
  });
  await sharp(sang, { raw: { width: M * temps.length, height: M, channels: 4 } })
    .png().toFile(path.join(dossier, "sang.png"));

  /* ── La bulle de parole ───────────────────────────────────────────────
   * Le signe qu'un personnage a quelque chose à dire qu'on n'a pas encore
   * entendu. Petite, au-dessus de la tête, avec ses trois points : c'est le
   * signe universel, inutile d'en inventer un autre.
   */
  const B = 16;
  const bulle = toile(B, B);
  const dedans = (x: number, y: number) => x >= 2 && x <= 13 && y >= 2 && y <= 10;
  const queue = (x: number, y: number) => y >= 11 && y <= 13 && x >= 5 && x <= 5 + (13 - y);
  for (let y = 0; y < B; y++) {
    for (let x = 0; x < B; x++) {
      const corps = dedans(x, y) || queue(x, y);
      if (!corps) continue;
      // Contour : tout pixel du corps qui touche le vide.
      const bord = ![[1, 0], [-1, 0], [0, 1], [0, -1]].every(([dx, dy]) =>
        dedans(x + dx, y + dy) || queue(x + dx, y + dy));
      poser(bulle, B, x, y, bord ? PAL.noir : PAL.blanc, B);
    }
  }
  // Les trois points, qui font lire « il a quelque chose à dire ».
  for (const x of [5, 8, 11]) poser(bulle, B, x, 6, PAL.acier, B);

  await sharp(bulle, { raw: { width: B, height: B, channels: 4 } })
    .png().toFile(path.join(dossier, "bulle.png"));

  /* ── Le mobilier ──────────────────────────────────────────────────────
   * Assemblé depuis `jeu/art/objets/`, une image par sorte, dans l'ordre que
   * le moteur attend. Les silhouettes calculées qui tenaient ici ont servi
   * jusqu'à ce qu'on ait mieux : un trône dessiné au compas reste un trône
   * dessiné au compas.
   *
   * Trente-deux pixels, comme les personnages : un trône et une bannière sont
   * plus hauts qu'une tuile, et se posent calés par le bas.
   */
  const O = 32;
  const SORTES = sortesDeMobilier();
  const source = path.join(ROOT, "jeu", "art", "objets");
  const pieces: sharp.OverlayOptions[] = [];
  for (const [i, sorte] of SORTES.entries()) {
    pieces.push({
      input: await sharp(path.join(source, `${sorte}.png`))
        .resize(O, O, { kernel: "nearest", fit: "contain",
          background: { r: 0, g: 0, b: 0, alpha: 0 } }).toBuffer(),
      left: i * O, top: 0,
    });
  }
  await sharp({ create: { width: O * SORTES.length, height: O, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(pieces).png().toFile(path.join(dossier, "objets.png"));

  /* ── La carte du continent ────────────────────────────────────────────
   *
   * Dessinée cellule par cellule depuis la grille de `lib/carte.ts`, avec un
   * trait sombre partout où la terre touche la mer. Le trait de côte n'est pas
   * décoratif : sans lui, une plaine verte contre une mer bleue à cinq pixels
   * par cellule se lit comme deux aplats, non comme un rivage.
   */
  const carte = toile(LARGEUR, HAUTEUR);
  const COTES = [[1, 0], [-1, 0], [0, 1], [0, -1]] as const;
  for (let cy = 0; cy < GRILLE.length; cy++) {
    for (let cx = 0; cx < GRILLE[0].length; cx++) {
      const t = terrain(cx, cy);
      const fond = COULEURS[t];

      for (let y = 0; y < CELLULE; y++) {
        for (let x = 0; x < CELLULE; x++) {
          let teinte: readonly number[] = fond;

          /* La montagne se strie plutôt que de s'aplatir.
           *
           * Un aplat gris sur un quart de la carte se lit comme une tache, non
           * comme une chaîne. Une diagonale claire une ligne sur deux suffit à
           * y remettre du relief à cinq pixels par cellule. */
          if (t === "montagne" && (x + y + cx) % 4 === 0) teinte = [0xa6, 0xa8, 0xb2];
          // Le désert se pique, la forêt se moutonne : même remède, autre grain.
          if (t === "desert" && (x * 2 + y + cy) % 5 === 0) teinte = [0xf0, 0xd1, 0x74];
          if (t === "foret" && (x + y * 2 + cx) % 5 === 0) teinte = [0x1c, 0x7a, 0x4e];

          poser(carte, LARGEUR, cx * CELLULE + x, cy * CELLULE + y, [...teinte, 255], HAUTEUR);
        }
      }

      /* Le trait de côte, arête par arête et non tout autour de la cellule.
       *
       * Peindre l'anneau entier de chaque cellule de rivage donnait un chapelet
       * de perles : deux cellules voisines dessinaient chacune leur contour, et
       * la ligne se refermait sur elle-même à chaque pas. On ne peint que le
       * côté qui touche l'eau, et le trait redevient continu. */
      if (t === "mer" || t === "parchemin") continue;
      for (const [dx, dy] of COTES) {
        const v = terrain(cx + dx, cy + dy);
        if (v !== "mer" && v !== "parchemin") continue;
        for (let i = 0; i < CELLULE; i++) {
          const x = dx === 0 ? i : (dx > 0 ? CELLULE - 1 : 0);
          const y = dy === 0 ? i : (dy > 0 ? CELLULE - 1 : 0);
          poser(carte, LARGEUR, cx * CELLULE + x, cy * CELLULE + y,
            [...COULEURS.cote, 255], HAUTEUR);
        }
      }
    }
  }
  await sharp(carte, { raw: { width: LARGEUR, height: HAUTEUR, channels: 4 } })
    .png().toFile(path.join(dossier, "carte.png"));

  const ICONES = lesIcones();
  const vignettes: sharp.OverlayOptions[] = [];
  for (const [i, nom] of ICONES.entries()) {
    vignettes.push({
      input: await sharp(path.join(ROOT, "jeu", "art", "inventaire", `${nom}.png`))
        .resize(O, O, { kernel: "nearest", fit: "contain",
          background: { r: 0, g: 0, b: 0, alpha: 0 } }).toBuffer(),
      left: i * O, top: 0,
    });
  }
  await sharp({ create: { width: O * Math.max(ICONES.length, 1), height: O, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(vignettes).png().toFile(path.join(dossier, "inventaire.png"));

  return { taillade: arcs.length, feu: battements.length, eclat: rayons.length,
    sang: temps.length, objets: SORTES.length, icones: ICONES.length };
}

/**
 * Les sortes de mobilier, dans l'ordre où la planche les range.
 *
 * Lues dans le dossier, jamais énumérées. Une liste écrite à la main devait
 * s'accorder avec celle du moteur, et deux listes ne s'accordent pas longtemps :
 * la liste des planches à copier du lanceur est restée figée sur deux fichiers
 * pendant que dix existaient, et le jeu se lançait sans Kira ni la Reine sans
 * que rien ne le signale.
 *
 * L'ordre alphabétique n'a rien de nécessaire — il est seulement stable, ce qui
 * est tout ce qu'on demande à un ordre que deux programmes doivent partager.
 * Le moteur le lit dans `monde.json` : il ne le devine pas.
 */
/** Les icônes de ce qu'on porte, dans l'ordre de la planche `inventaire.png`. */
function lesIcones(): string[] {
  const source = path.join(ROOT, "jeu", "art", "inventaire");
  if (!fs.existsSync(source)) return [];
  return fs.readdirSync(source).filter((f) => f.endsWith(".png")).map((f) => f.slice(0, -4)).sort();
}

function sortesDeMobilier(): string[] {
  const source = path.join(ROOT, "jeu", "art", "objets");
  if (!fs.existsSync(source)) return [];
  return fs.readdirSync(source)
    .filter((f) => f.endsWith(".png"))
    .map((f) => f.slice(0, -4))
    .sort();
}

type Personnage = {
  /** Son numéro au Codex — le même que sur le site. */
  rang: number;
  nom: string;
  role: string;
  tomes: number[];
  planche: string | null;
  /** Le visage montré pendant qu'il parle, s'il en a un. */
  portrait: string | null;
  /** Les humeurs déclinées de ce visage, s'il y en a. */
  humeurs: string[];
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

  // Numérotées dans l'ordre du site : un personnage porte un seul numéro.
  for (const [i, f] of ordered(fiches).entries()) {
    if (f.kind === "personnage") {
      const planche = path.join(ART, "personnages", `${f.id}.png`);
      personnages[f.id] = {
        rang: i + 1,
        nom: f.name,
        role: f.gloss,
        tomes: f.books ?? [],
        planche: fs.existsSync(planche) ? `${f.id}.png` : null,
        portrait: fs.existsSync(path.join(ART, "portraits", `${f.id}.png`)) ? `portrait-${f.id}.png` : null,
        humeurs: humeursDe(f.id),
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

  /* Ce que les passes de lecture ont manqué, rétabli depuis corrections.json.
   *
   * Après la boucle sur les entrées du Codex, jamais avant : un lieu déclaré à
   * la main ne doit pas masquer celui que l'Oracle finira peut-être par
   * relever. Si les deux existent, c'est le relevé qui gagne. */
  for (const l of loadLieuxAjoutes(ROOT)) {
    if (lieux[l.id]) {
      console.log(`  ${C.dim}${l.id} : relevé par l'Oracle, la correction devient inutile${C.off}`);
      continue;
    }
    const tuiles = path.join(ART, "lieux", `${l.id}.png`);
    lieux[l.id] = {
      nom: l.nom, role: l.role,
      tuiles: fs.existsSync(tuiles) ? `${l.id}.png` : null,
    };
    console.log(`  ${C.yellow}${l.id} ajouté à la main — ${l.motif.slice(0, 70)}…${C.off}`);
  }

  const monde = {
    version: 1,
    batiLe: new Date().toISOString().slice(0, 10),
    provenance: "Fiches du Codex — résumés produits par l'Oracle. Aucune phrase des romans.",
    personnages,
    peuples,
    lieux,
    mobilier: sortesDeMobilier(),
    /* Ce qu'on peut ramasser, rassemblé depuis les salles.
     *
     * La description vit dans le meuble qui le contient — c'est là qu'on
     * l'écrit et là qu'on la relit. Mais le sac se consulte n'importe où, y
     * compris dans une salle qui n'a jamais porté l'objet : il faut donc que le
     * moteur puisse retrouver un texte sans avoir la salle sous la main. */
    prises: {} as Record<string, Prise & { ou: string; image: number }>,
    /** Les emplacements d'équipement, dans l'ordre où le sac les montre. */
    emplacements: ["arme", "armure", "bouclier", "casque", "bottes"],
    /** Ce que Wellan porte au premier pas. */
    depart: [] as { id: string; emplacement: string }[],
    sons: SONS,
    /* Les escales de la carte : où l'on peut se rendre, et où l'on débarque. */
    carte: {
      cellule: CELLULE, largeur: LARGEUR, hauteur: HAUTEUR,
      escales: ESCALES,
    },
    /* Rempli après coup : les musiques se rendent en même temps que les
     * effets, donc après que ce fichier a été écrit une première fois. */
    musiques: [] as { nom: string; images: number; duree: number }[],
  };

  const fichier = path.join(SORTIE, "monde.json");
  fs.writeFileSync(fichier, JSON.stringify(monde, null, 1) + "\n");

  const avecPortrait = Object.values(personnages).filter((p) => p.portrait).length;
  const avecPlanche = Object.values(personnages).filter((p) => p.planche).length;
  const avecTuiles = Object.values(lieux).filter((l) => l.tuiles).length;
  const poids = (fs.statSync(fichier).size / 1024).toFixed(0);

  console.log(`${C.green}✓${C.off} ${path.relative(ROOT, fichier)}  ${poids} Ko`);
  const humeurs = Object.values(personnages).reduce((n, p) => n + p.humeurs.length, 0);
  console.log(`  ${C.dim}${Object.keys(personnages).length} personnages, dont ${avecPlanche} avec planche et ${avecPortrait} avec portrait (${humeurs} humeurs)${C.off}`);
  console.log(`  ${C.dim}${Object.keys(lieux).length} lieux, dont ${avecTuiles} avec tuiles${C.off}`);
  const peuplesArmes = Object.values(peuples).filter((p) => p.planche).length;
  console.log(`  ${C.dim}${Object.keys(peuples).length} peuples, dont ${peuplesArmes} avec planche${C.off}`);

  /* Les salles sont écrites à la main : ce sont des décisions de mise en scène,
   * pas des données à déduire. Le script se contente de les valider. */
  const salles = path.join(SORTIE, "salles");
  let fautes = 0;

  /* Deux registres, et c'est la différence qui compte.
   *
   * Une porte qui vise une salle absente, qui dépose hors du plancher ou qui
   * n'a pas de retour est une faute : la machine en juge seule et le jeu casse.
   * Deux meubles trop proches est un avertissement : la règle des trois tuiles
   * est prudente, et il arrive qu'on ne se tienne jamais entre les deux. Faire
   * échouer la production là-dessus reviendrait à interdire une mise en scène
   * que personne n'a regardée. */
  let regards = 0;

  /* Toutes les salles d'abord : une porte se juge sur celle qu'elle vise, et
   * l'on ne peut pas la vérifier en lisant les fichiers un par un. */
  type Case = { x: number; y: number };
  type Prise = {
    id: string; nom: string; texte: string[];
    categorie?: string; emplacement?: string; bonus?: Record<string, number>;
  };
  type Salle = {
    id?: string; lieu?: string; nom?: string; taille?: [number, number];
    depart?: [number, number];
    personnages?: { fiche: string; des?: string; dit?: { qui: string; dit: string }[]; donne?: Prise }[];
    objets?: (Case & { type?: string; nom?: string; contient?: Prise | Prise[] })[];
    passages?: (Case & { vers: string; arrivee: [number, number]; des?: string; verrou?: string })[];
  };
  const toutes: Record<string, Salle> = {};
  for (const f of fs.existsSync(salles) ? fs.readdirSync(salles) : []) {
    if (!f.endsWith(".json")) continue;
    toutes[f.replace(/\.json$/, "")] = JSON.parse(fs.readFileSync(path.join(salles, f), "utf8"));
  }

  /* Où les scènes font entrer quelqu'un, salle par salle.
   *
   * Un personnage amené par une étape ne figure pas dans le fichier de salle :
   * il n'existe qu'au moment où le chapitre le convoque. Le contrôle de
   * voisinage ne le voyait donc pas, et rien n'empêchait de meubler la case où
   * la Reine de Shola paraît. Le défaut se serait manifesté en jeu par une
   * étape qu'on ne peut pas finir, sans que rien ne le dise. */
  const campagne = JSON.parse(
    fs.readFileSync(path.join(SORTIE, "campagne.json"), "utf8"),
  ).chapitres as string[];

  const scenes = path.join(SORTIE, "scenes");
  type Etape = {
    id?: string;
    apparaissent?: (Case & { fiche: string })[];
    disparaissent?: string[];
    attend?: { parler?: string; parler_tous?: string[]; vague_defaite?: boolean };
    vague?: { espece: string; nombre?: number }[];
    dialogues?: Record<string, unknown>;
  };
  type Scene = { salle?: string; etapes?: Etape[]; fin?: Etape };
  const toutesScenes: Record<string, Scene> = {};
  for (const f of fs.existsSync(scenes) ? fs.readdirSync(scenes) : []) {
    if (!f.endsWith(".json")) continue;
    toutesScenes[f.replace(/\.json$/, "")] = JSON.parse(fs.readFileSync(path.join(scenes, f), "utf8"));
  }

  /* Deux tuiles d'écart ne suffisent pas ; il en faut trois. À égale distance
   * de deux voisins, on aborde l'un pour l'autre, et se rapprocher n'y change
   * rien. Le défaut ne signale rien : il bloque une étape, voilà tout. C'est
   * pourquoi il se mesure ici plutôt qu'à l'œil sur une capture. */
  const ECART = 3;
  const loin = (a: Case, b: Case) => Math.hypot(a.x - b.x, a.y - b.y) >= ECART;
  const mobilier = sortesDeMobilier();

  /* Ce que Wellan porte déjà.
   *
   * Ces deux pièces ne sont dans aucun coffre : on ne les trouve pas, on les a.
   * Le sprite les montre depuis toujours — le surcot deux tons est décrit par
   * le texte comme la chose qui doit se reconnaître d'un Chevalier à l'autre —
   * et l'écran d'équipement mentait en le laissant nu.
   *
   * **Leurs bonus ne changent aucun nombre du combat aujourd'hui** : force 5+3
   * rend toujours un dégât d'épée, défense 2 toujours zéro de réduction. C'est
   * délibéré. Donner un équipement de départ ne doit pas rééquilibrer un jeu
   * dont dix-huit chapitres ont été éprouvés à l'équilibre d'avant.
   */
  const DEPART: (Prise & { emplacement: string })[] = [
    {
      id: "epee-de-wellan", nom: "Ton épée", categorie: "equipement",
      emplacement: "arme", bonus: { force: 3 },
      texte: [
        "Une lame d'homme, enfin. Celle qu'on t'a remise le jour où tu as cessé d'être Écuyer.",
        "Le pommeau porte une émeraude que personne n'a jamais estimée, et qu'on ne vendra pas.",
      ],
    },
    {
      id: "surcot-d-emeraude", nom: "Ton surcot", categorie: "equipement",
      emplacement: "armure", bonus: { defense: 2 },
      texte: [
        "Vert et noir, partagés dans la hauteur : la croix d'Émeraude en noir sur le vert, un dragon vert sur le noir.",
        "Il y en a sept exactement pareils. C'est le propos : de loin, on ne doit pas savoir lequel des sept on regarde.",
      ],
    },
  ];

  const icones = lesIcones();
  for (const d of DEPART) {
    const image = icones.indexOf(d.id);
    if (image < 0) {
      console.log(`  ${C.red}équipement de départ « ${d.id} » sans icône dans jeu/art/inventaire/${C.off}`);
      fautes++;
    }
    monde.prises[d.id] = { ...d, ou: "À toi depuis le premier jour", image };
  }
  monde.depart = DEPART.map((d) => ({ id: d.id, emplacement: d.emplacement }));

  /* Une pièce se recense de la même façon qu'elle vienne d'un coffre ou d'une
   * main tendue : mêmes catégories, même icône obligatoire, même refus de la
   * ramasser deux fois. La seule différence est la ligne « où » que le sac
   * affichera — l'endroit pour un meuble, la personne pour un présent. */
  const recenser = (prise: Prise, source: string, ou: string) => {
    if (monde.prises[prise.id]) {
      console.log(`  ${C.red}${source} : « ${prise.id} » se ramasse déjà ailleurs${C.off}`);
      fautes++;
      return;
    }
    const categorie = prise.categorie ?? "objet";
    if (categorie !== "objet" && categorie !== "equipement") {
      console.log(`  ${C.red}${source} : « ${prise.id} » d'une catégorie inconnue « ${categorie} »${C.off}`);
      fautes++;
    }
    /* Les deux catégories ne se mélangent pas, et la règle se tient des deux
     * côtés : un équipement sans emplacement ne pourrait pas se porter, un
     * objet qui en porte un se retrouverait équipable dans une liste qui ne le
     * propose pas. */
    if (categorie === "equipement" && !monde.emplacements.includes(prise.emplacement ?? "")) {
      console.log(`  ${C.red}${source} : l'équipement « ${prise.id} » n'a pas d'emplacement connu${C.off}`);
      fautes++;
    }
    if (categorie === "objet" && prise.emplacement) {
      console.log(`  ${C.red}${source} : l'objet « ${prise.id} » porte un emplacement, ce qui n'a pas de sens${C.off}`);
      fautes++;
    }
    const image = icones.indexOf(prise.id);
    if (image < 0) {
      console.log(`  ${C.red}${source} : « ${prise.id} » n'a pas d'icône dans jeu/art/inventaire/${C.off}`);
      fautes++;
    }
    monde.prises[prise.id] = { ...prise, categorie, ou, image };
  };

  for (const [id, salle] of Object.entries(toutes)) {
    for (const o of salle.objets ?? []) {
      if (!o.contient) continue;
      for (const prise of Array.isArray(o.contient) ? o.contient : [o.contient]) {
        recenser(prise, `${id}.json`, salle.nom ?? id);
      }
    }
    for (const p of salle.personnages ?? []) {
      if (!p.donne) continue;
      /* Un présent sans un mot serait un ramassage déguisé : c'est la réplique
       * qui le motive, et c'est elle qui déclenche la fenêtre en jeu. Un
       * donneur muet ne pourrait jamais rien donner. */
      if (!p.dit?.length) {
        console.log(`  ${C.red}${id}.json : « ${p.fiche} » donne quelque chose sans rien dire${C.off}`);
        fautes++;
      }
      recenser(p.donne, `${id}.json`, `Donné par ${personnages[p.fiche]?.nom ?? p.fiche}`);
    }
  }

  for (const [id, salle] of Object.entries(toutes)) {
    const f = `${id}.json`;
    const [large, haut] = salle.taille ?? [0, 0];
    const dedans = (c: Case) => c.x >= 0 && c.x < large && c.y >= 0 && c.y < haut;

    for (const p of salle.personnages ?? []) {
      if (!personnages[p.fiche]) {
        console.log(`  ${C.red}${f} : fiche inconnue « ${p.fiche} »${C.off}`);
        fautes++;
      }
      /* Un habitant qui n'arrive qu'à partir d'un chapitre doit en nommer un
       * qui existe — sinon il n'apparaît jamais, en silence. */
      if (p.des !== undefined && !campagne.includes(p.des)) {
        console.log(`  ${C.red}${f} : « ${p.fiche} » arrive au chapitre « ${p.des} », qui n'est pas dans la campagne${C.off}`);
        fautes++;
      }
      /* Une réplique d'habitant doit se dire à quelqu'un. `qui` nomme la voix ;
       * s'il ne correspond à aucune fiche, le cadre affiche un nom vide. */
      for (const l of p.dit ?? []) {
        if (l.qui !== "recit" && l.qui !== "wellan" && !personnages[l.qui]) {
          console.log(`  ${C.red}${f} : « ${p.fiche} » fait parler « ${l.qui} », qui n'a pas de fiche${C.off}`);
          fautes++;
        }
      }
    }
    /* Une sorte inconnue ne casse rien : le moteur prend la première case de la
     * planche et pose un arbre au milieu d'un dortoir. C'est précisément le
     * genre de faute qu'on ne voit qu'en regardant, donc celui qu'il faut
     * mesurer. */
    for (const o of salle.objets ?? []) {
      if (o.type && !mobilier.includes(o.type)) {
        console.log(`  ${C.red}${f} : sorte de mobilier inconnue « ${o.type} »${C.off}`);
        fautes++;
      }
    }
    if (salle.lieu && !lieux[salle.lieu]) {
      console.log(`  ${C.red}${f} : lieu inconnu « ${salle.lieu} »${C.off}`);
      fautes++;
    }

    /* Ce qui s'aborde et qui existe indépendamment de tout chapitre : le
     * mobilier qui porte un texte, et les portes.
     *
     * Les personnages sont écartés d'ici et jugés plus bas, scène par scène. Ils
     * y étaient, et chaque salle jouée par trois chapitres rendait le même
     * avertissement quatre fois — une fois pour la salle, trois pour les
     * chapitres. Un contrôle qu'on lit en diagonale ne contrôle plus rien. */
    const abordables: (Case & { quoi: string })[] = [
      ...(salle.objets ?? []).filter((o) => o.nom).map((o) => ({ x: o.x, y: o.y, quoi: o.nom ?? o.type ?? "objet" })),
      ...(salle.passages ?? []).map((p) => ({ x: p.x, y: p.y, quoi: `porte → ${p.vers}` })),
    ];
    for (const a of abordables) {
      if (!dedans(a)) {
        console.log(`  ${C.red}${f} : « ${a.quoi} » en ${a.x},${a.y} hors des ${large}×${haut} tuiles${C.off}`);
        fautes++;
      }
    }
    for (let i = 0; i < abordables.length; i++) {
      for (let j = i + 1; j < abordables.length; j++) {
        if (loin(abordables[i], abordables[j])) continue;
        console.log(`  ${C.yellow}${f} : « ${abordables[i].quoi} » et « ${abordables[j].quoi} » à moins de ${ECART} tuiles — à regarder${C.off}`);
        regards++;
      }
    }

    /* Une porte tient sur un bord, vise une salle qui existe, et dépose
     * ailleurs qu'au milieu d'un meuble ou sur une autre porte. */
    for (const porte of salle.passages ?? []) {
      const bord = porte.x <= 0 || porte.y <= 0 || porte.x >= large - 1 || porte.y >= haut - 1;
      if (!bord) {
        console.log(`  ${C.red}${f} : la porte en ${porte.x},${porte.y} n'est sur aucun bord${C.off}`);
        fautes++;
      }
      const ailleurs = toutes[porte.vers];
      if (!ailleurs) {
        console.log(`  ${C.red}${f} : porte vers une salle inconnue « ${porte.vers} »${C.off}`);
        fautes++;
        continue;
      }
      const [al, ah] = ailleurs.taille ?? [0, 0];
      const ou = { x: porte.arrivee?.[0] ?? -1, y: porte.arrivee?.[1] ?? -1 };
      if (ou.x < 0 || ou.x >= al || ou.y < 0 || ou.y >= ah) {
        console.log(`  ${C.red}${f} : la porte vers ${porte.vers} dépose en ${ou.x},${ou.y}, hors des ${al}×${ah} tuiles${C.off}`);
        fautes++;
      }
      /* On arrive à côté d'une porte, jamais dessus : arriver sur le seuil du
       * retour mettrait l'invite du retour sous le nez au premier pas. */
      for (const retour of ailleurs.passages ?? []) {
        if (retour.x === ou.x && retour.y === ou.y) {
          console.log(`  ${C.red}${f} : la porte vers ${porte.vers} dépose sur une autre porte, en ${ou.x},${ou.y}${C.off}`);
          fautes++;
        }
      }
      for (const o of ailleurs.objets ?? []) {
        if (!o.nom || loin(o, ou)) continue;
        console.log(`  ${C.yellow}${f} : la porte vers ${porte.vers} dépose à moins de ${ECART} tuiles de « ${o.nom} » — à regarder${C.off}`);
        regards++;
      }
      /* Une porte qui s'ouvre à partir d'un chapitre doit nommer un chapitre qui
       * existe, et dire pourquoi elle est fermée : sans le motif, le joueur bute
       * sur un mur muet et croit à un défaut. */
      if (porte.des !== undefined) {
        if (!campagne.includes(porte.des)) {
          console.log(`  ${C.red}${f} : la porte vers ${porte.vers} s'ouvre au chapitre « ${porte.des} », qui n'est pas dans la campagne${C.off}`);
          fautes++;
        }
        if (!porte.verrou) {
          console.log(`  ${C.red}${f} : la porte vers ${porte.vers} se verrouille sans dire pourquoi${C.off}`);
          fautes++;
        }
      }

      /* Un aller sans retour laisse le joueur enfermé, et rien ne le dit. */
      if (!(ailleurs.passages ?? []).some((r) => r.vers === id)) {
        console.log(`  ${C.red}${f} : la porte vers ${porte.vers} n'a pas de retour${C.off}`);
        fautes++;
      }
    }

    const noms = (salle.personnages ?? []).map((p: { fiche: string }) => personnages[p.fiche]?.nom ?? "?");
    const decor = [
      `${(salle.objets ?? []).length} objets`,
      ...((salle.passages ?? []).length ? [`${(salle.passages ?? []).length} portes`] : []),
    ].join(", ");
    console.log(`  ${C.dim}${f} → ${large}×${haut} tuiles, ${decor}${noms.length ? `, ${noms.join(", ")}` : ""}${C.off}`);
  }

  /* Le voisinage pendant qu'un chapitre se joue.
   *
   * On refait ce que fait le moteur : l'effectif de la salle, corrigé étape par
   * étape par les entrées et les sorties. Comparer tous les `apparaissent` d'un
   * coup accusait Armène du chapitre I,1 de gêner Armène du I,2, et la Reine de
   * gêner une servante repartie une étape plus tôt — trois faux avertissements
   * pour un vrai, ce qui fait qu'on cesse de les lire. */
  for (const [id, scene] of Object.entries(toutesScenes)) {
    const salle = toutes[String(scene.salle ?? "")];
    if (!salle) continue;
    const fixes = [
      ...(salle.objets ?? []).filter((o) => o.nom).map((o) => ({ x: o.x, y: o.y, quoi: o.nom ?? "objet" })),
      ...(salle.passages ?? []).map((p) => ({ x: p.x, y: p.y, quoi: `porte → ${p.vers}` })),
    ];
    let present = (salle.personnages ?? []).map((p) => ({
      ...(p as unknown as Case), quoi: p.fiche, fiche: p.fiche,
    }));
    const deja = new Set<string>();

    /* La clôture est une étape comme les autres : c'est le moteur qui les
     * enchaîne ainsi, et un `fin` sans condition laisse le chapitre ouvert
     * pour toujours — le premier piège du format. */
    const etapes: Etape[] = [...(scene.etapes ?? []), ...(scene.fin ? [scene.fin] : [])];
    if (scene.fin && !scene.fin.attend) {
      console.log(`  ${C.red}${id} : le bloc « fin » n'a pas de condition — le chapitre ne s'achèvera jamais${C.off}`);
      fautes++;
    }

    for (const [n, etape] of etapes.entries()) {
      for (const parti of etape.disparaissent ?? []) {
        present = present.filter((p) => p.fiche !== parti);
      }
      for (const e of etape.apparaissent ?? []) {
        present.push({ x: e.x, y: e.y, quoi: e.fiche, fiche: e.fiche });
      }

      /* Ce qu'une étape exige doit être là pour qu'on puisse le faire.
       *
       * C'est la faute qui coûte le plus cher à trouver : le chapitre se lance,
       * la salle est correcte, et l'objectif ne s'accomplit jamais parce que
       * celui à qui il faut parler n'a pas été posé. Rien ne le signale en jeu
       * — on cherche dans le moteur, puis dans la salle, et l'on finit par
       * relire la scène. Ici, cela coûte zéro seconde.
       */
      const ici = new Set(present.map((p) => p.fiche));
      const nom = etape.id ?? (n === etapes.length - 1 && scene.fin ? "fin" : `étape ${n + 1}`);
      const exiges = [
        ...(etape.attend?.parler ? [etape.attend.parler] : []),
        ...(etape.attend?.parler_tous ?? []),
      ];
      for (const qui of exiges) {
        if (!ici.has(qui)) {
          console.log(`  ${C.red}${id} · ${nom} : attend qu'on parle à « ${qui} », qui n'est pas dans la salle${C.off}`);
          fautes++;
        }
      }
      if (etape.attend?.vague_defaite && !(etape.vague ?? []).length) {
        console.log(`  ${C.red}${id} · ${nom} : attend une vague défaite, mais l'étape n'en lève aucune${C.off}`);
        fautes++;
      }
      if (!etape.attend) {
        console.log(`  ${C.red}${id} · ${nom} : aucune condition — le chapitre s'arrête là${C.off}`);
        fautes++;
      }

      /* Une réplique écrite pour quelqu'un d'absent ne se lira jamais. Ce n'est
       * pas une faute — on rattrape après la clôture, où toutes les étapes
       * redeviennent disponibles — mais c'est presque toujours un oubli. */
      for (const qui of Object.keys(etape.dialogues ?? {})) {
        if (qui !== "wellan" && !ici.has(qui)) {
          console.log(`  ${C.yellow}${id} · ${nom} : réplique écrite pour « ${qui} », absent de la salle — à regarder${C.off}`);
          regards++;
        }
      }

      const tous = [...present, ...fixes];
      for (let i = 0; i < tous.length; i++) {
        for (let j = i + 1; j < tous.length; j++) {
          if (loin(tous[i], tous[j])) continue;
          const cle = [tous[i].quoi, tous[j].quoi].sort().join(" / ");
          if (deja.has(cle)) continue;
          deja.add(cle);
          console.log(`  ${C.yellow}${id} étape ${n + 1} : « ${tous[i].quoi} » et « ${tous[j].quoi} » à moins de ${ECART} tuiles — à regarder${C.off}`);
          regards++;
        }
      }
    }
  }

  silhouette(path.join(SORTIE, "silhouette.png"))
    .then(() => effets(SORTIE))
    .then(async (n) => {
      console.log(`  ${C.dim}silhouette d'attente écrite${C.off}`);
      console.log(`  ${C.dim}effets dessinés : taillade ${n.taillade}, feu ${n.feu}, éclat ${n.eclat}, sang ${n.sang}, mobilier ${n.objets}, icônes ${n.icones}${C.off}`);

      /* Un son ne se regarde pas. Une planche fausse se voit sur une capture,
       * un fichier son vide ne se voit nulle part — on imprime donc ce qu'on
       * vient d'écrire, durée comprise, faute de mieux. */
      const sons = await ecrireLesSons(path.join(SORTIE, "sons"));
      console.log(`  ${C.dim}sons calculés : ${sons.map((x) => `${x.nom} ${x.duree.toFixed(2)}s`).join(", ")}${C.off}`);

      const muet = sons.filter((x) => x.octets <= 44 || x.pic < 0.05);
      if (muet.length) {
        console.log(`  ${C.red}${muet.length} son(s) muet(s) : ${muet.map((x) => `${x.nom} (pic ${x.pic.toFixed(3)})`).join(", ")}${C.off}`);
        fautes++;
      }
      /* Une enveloppe qui ne retombe pas à zéro claque à la coupure, et un son
       * de combat se joue cent fois par bataille. */
      const claque = sons.filter((x) => x.fin > 0.02);
      if (claque.length) {
        console.log(`  ${C.red}${claque.length} son(s) coupé(s) net : ${claque.map((x) => `${x.nom} (fin ${x.fin.toFixed(3)})`).join(", ")}${C.off}`);
        fautes++;
      }

      /* Les musiques. Un morceau porte le nom du lieu qu'il accompagne : c'est
       * le fichier qui fait la correspondance, non une table. Sans fichier au
       * nom du lieu, le lieu est silencieux, et c'est tout ce qu'il y a à
       * savoir. */
      const musiques = await ecrireLesMusiques(path.join(SORTIE, "musiques"));
      console.log(`  ${C.dim}musiques rendues : ${musiques.map((m) => `${m.nom} ${m.duree.toFixed(1)}s`).join(", ")}${C.off}`);

      /* La couture, seule chose qu'une machine puisse juger d'une boucle : de
       * combien le signal saute du dernier échantillon au premier. Plus grande
       * qu'un écart ordinaire entre voisins, elle claque à chaque tour. */
      const cousu = musiques.filter((m) => m.couture > 0.01);
      if (cousu.length) {
        console.log(`  ${C.red}${cousu.length} boucle(s) qui claquent : ${cousu.map((m) => `${m.nom} (couture ${m.couture.toFixed(4)})`).join(", ")}${C.off}`);
        fautes++;
      }
      monde.musiques = musiques.map((m) => ({ nom: m.nom, images: m.images, duree: m.duree }));
      fs.writeFileSync(fichier, JSON.stringify(monde, null, 1) + "\n");
      if (regards) console.log(`  ${C.yellow}${regards} voisinage(s) sous trois tuiles — la machine ne tranche pas, l'œil oui${C.off}`);
      if (fautes) process.exitCode = 1;
    });
}

main();
