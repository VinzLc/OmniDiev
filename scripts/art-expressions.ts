/**
 * Décline un portrait en plusieurs humeurs, en repeignant ses seuls traits.
 *
 * Trois voies ont été essayées avant celle-ci. Une description d'expression
 * avec image d'amorce : à toutes les forces, de 150 à 850, les cinq humeurs
 * rendaient le même visage impassible. Une génération sans amorce : cinq
 * humeurs, cinq hommes différents. Un repeint par `inpaint` : l'humeur arrivait
 * mais la barbe disparaissait et les yeux perdaient leur bleu.
 *
 * Restait ce que le projet fait chaque fois qu'un modèle refuse d'obéir sur un
 * détail : viser le détail soi-même. Des sourcils et une bouche sont quelques
 * dizaines de pixels à des places qu'on peut mesurer. Le reste du portrait
 * n'est jamais touché, donc c'est le même homme — non par chance, par
 * construction.
 *
 * Usage :
 *   npm run art:expressions -- wellan
 */
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";

const ROOT = path.resolve(import.meta.dirname, "..");
const PORTRAITS = path.join(ROOT, "jeu", "art", "portraits");
const C = { red: "\x1b[31m", green: "\x1b[32m", dim: "\x1b[2m", off: "\x1b[0m" };

type Trait = {
  /** Pente du sourcil : positive = extrémité interne plus basse, donc dure. */
  pente: number;
  /** Décalage vertical des sourcils : négatif = relevés, donc ouverts. */
  hauteur: number;
  /** Courbure de la bouche : positive = coins tombants. */
  bouche: number;
  /** La bouche s'entrouvre-t-elle ? */
  ouverte?: boolean;
};

const HUMEURS: Record<string, Trait> = {
  grave:    { pente: 1.4, hauteur: 0, bouche: 0.9 },
  colere:   { pente: 2.6, hauteur: 1, bouche: 1.4 },
  doux:     { pente: -1.0, hauteur: -1, bouche: -1.2 },
  trouble:  { pente: -1.8, hauteur: -3, bouche: 0, ouverte: true },
  resolu:   { pente: 0.6, hauteur: 0, bouche: -0.3 },
};

type Image = { data: Buffer; l: number; h: number; ch: 1 | 2 | 3 | 4 };

const lire = (i: Image, x: number, y: number) => {
  const o = (y * i.l + x) * i.ch;
  return [i.data[o], i.data[o + 1], i.data[o + 2], i.data[o + 3]];
};
const ecrire = (i: Image, x: number, y: number, c: number[]) => {
  if (x < 0 || y < 0 || x >= i.l || y >= i.h) return;
  const o = (y * i.l + x) * i.ch;
  i.data[o] = c[0]; i.data[o + 1] = c[1]; i.data[o + 2] = c[2]; i.data[o + 3] = 255;
};

/** Où sont les yeux : les pixels franchement bleus du visage. */
function yeux(i: Image) {
  const pts: [number, number][] = [];
  for (let y = 0; y < i.h; y++) {
    for (let x = 0; x < i.l; x++) {
      const [r, g, b, a] = lire(i, x, y);
      if (a > 16 && b > 140 && b > r + 40 && b > g + 20) pts.push([x, y]);
    }
  }
  if (!pts.length) return null;
  const ys = pts.map((p) => p[1]);
  const ligne = Math.round(ys.reduce((a, b) => a + b, 0) / ys.length);
  const g = pts.filter((p) => p[0] < i.l / 2).map((p) => p[0]);
  const d = pts.filter((p) => p[0] >= i.l / 2).map((p) => p[0]);
  if (!g.length || !d.length) return null;
  return {
    ligne,
    gauche: Math.round((Math.min(...g) + Math.max(...g)) / 2),
    droite: Math.round((Math.min(...d) + Math.max(...d)) / 2),
  };
}

/** La bouche : la rangée la plus sombre sous les yeux, dans la largeur du visage. */
function bouche(i: Image, sous: number, x0: number, x1: number) {
  let meilleure = sous + 14, record = 0;
  for (let y = sous + 10; y < sous + 30 && y < i.h; y++) {
    let n = 0;
    for (let x = x0; x <= x1; x++) {
      const [r, g, b, a] = lire(i, x, y);
      if (a > 16 && r < 90 && g < 80 && b < 80) n++;
    }
    if (n > record) { record = n; meilleure = y; }
  }
  return meilleure;
}

/** La carnation dominante d'une zone, pour effacer avant de redessiner. */
function carnation(i: Image, x0: number, y0: number, x1: number, y1: number) {
  const compte = new Map<string, number>();
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const [r, g, b, a] = lire(i, x, y);
      if (a < 16 || r < 120 || r < g + 10) continue;
      const k = `${r},${g},${b}`;
      compte.set(k, (compte.get(k) ?? 0) + 1);
    }
  }
  const meilleur = [...compte.entries()].sort((a, b) => b[1] - a[1])[0];
  return meilleur ? meilleur[0].split(",").map(Number) : [217, 165, 124];
}

async function decliner(id: string) {
  const socle = path.join(PORTRAITS, `${id}.png`);
  if (!fs.existsSync(socle)) {
    console.error(`${C.red}Portrait absent : ${path.relative(ROOT, socle)}${C.off}`);
    process.exit(1);
  }
  const { data, info } = await sharp(socle).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const base: Image = { data, l: info.width, h: info.height, ch: info.channels as 1 | 2 | 3 | 4 };

  const oeil = yeux(base);
  if (!oeil) {
    console.error(`${C.red}Yeux introuvables sur ${id} : il faut du bleu pour se repérer.${C.off}`);
    process.exit(1);
  }
  const largeur = Math.abs(oeil.droite - oeil.gauche);
  const lignBouche = bouche(base, oeil.ligne, oeil.gauche, oeil.droite);
  console.log(`${C.dim}${id} : yeux à y ${oeil.ligne} (x ${oeil.gauche} et ${oeil.droite}), bouche à y ${lignBouche}${C.off}`);

  const peau = carnation(base, oeil.gauche - 6, oeil.ligne - 12, oeil.droite + 6, oeil.ligne - 5);
  const encre = [26, 20, 16];

  for (const [nom, t] of Object.entries(HUMEURS)) {
    const img: Image = { data: Buffer.from(base.data), l: base.l, h: base.h, ch: base.ch };
    const demi = Math.max(3, Math.round(largeur * 0.19));

    for (const [cx, sens] of [[oeil.gauche, 1], [oeil.droite, -1]] as [number, number][]) {
      const haut = oeil.ligne - 6 + t.hauteur;
      // Effacer l'ancien sourcil : trois rangées de peau au-dessus de l'œil.
      for (let y = haut - 3; y <= haut + 3; y++)
        for (let x = cx - demi - 1; x <= cx + demi + 1; x++) ecrire(img, x, y, peau);
      // Puis le nouveau, incliné. `sens` retourne la pente pour le second œil,
      // sans quoi les deux sourcils pencheraient du même côté.
      for (let d = -demi; d <= demi; d++) {
        const y = Math.round(haut + (d * sens * t.pente) / demi);
        ecrire(img, cx + d, y, encre);
        ecrire(img, cx + d, y + 1, encre);
      }
    }

    // La bouche : on repeint la rangée trouvée, courbée selon l'humeur.
    const largBouche = Math.max(4, Math.round(largeur * 0.32));
    for (let d = -largBouche; d <= largBouche; d++) {
      const centre = Math.round((oeil.gauche + oeil.droite) / 2);
      const y = Math.round(lignBouche + (Math.abs(d) / largBouche) * t.bouche);
      ecrire(img, centre + d, y, encre);
      if (t.ouverte && Math.abs(d) < largBouche * 0.55) ecrire(img, centre + d, y + 1, encre);
    }

    const dest = path.join(PORTRAITS, `${id}-${nom}.png`);
    await sharp(img.data, { raw: { width: img.l, height: img.h, channels: img.ch } })
      .png().toFile(dest);
    console.log(`  ${C.green}✓${C.off} ${id}-${nom}.png`);
  }
}

const qui = process.argv.slice(2).filter((a) => !a.startsWith("-"));
if (!qui.length) {
  console.error("Quel portrait ? Exemple : npm run art:expressions -- wellan");
  process.exit(1);
}
for (const id of qui) await decliner(id);
