/**
 * Les musiques, séquencées.
 *
 * Et c'est ici que ce projet change de nature, ce qu'il vaut mieux dire que
 * laisser glisser. Les bruitages étaient **calculés** : un coup d'épée est du
 * bruit sous une enveloppe, une forme physique, comme un arc de taillade est
 * une forme géométrique. Une mélodie n'est pas une forme. Elle est **écrite**.
 *
 * Le moteur ci-dessous se calcule — oscillateurs, enveloppes, harmoniques. Le
 * morceau, lui, est composé, et il l'est par la machine qui écrit ce fichier,
 * non déduit du texte d'Anne Robillard. C'est la première chose du dépôt dont
 * on ne puisse pas dire qu'elle vient de l'œuvre. Elle vient de nous.
 *
 * En échange, la provenance reste entière : rien n'est acheté, rien ne descend
 * d'un service, tout se recalcule à l'octet près depuis ces quelques lignes.
 *
 * Les voix sont celles d'une console portable de l'époque visée : deux voies
 * d'impulsion et une triangulaire. La contrainte n'est pas nostalgique, elle
 * est utile — trois voix obligent à écrire une ligne qui tienne debout seule.
 */

import { TAUX, wav } from "./sons.ts";

/* ── Les hauteurs ─────────────────────────────────────────────────────── */

const DEMI_TONS: Record<string, number> = {
  C: 0, "C#": 1, D: 2, "D#": 3, E: 4, F: 5, "F#": 6, G: 7, "G#": 8, A: 9, "A#": 10, B: 11,
};

/** « A4 » → 440 Hz. Les bémols s'écrivent en dièses : si bémol est « A# ». */
function hz(nom: string): number {
  const m = /^([A-G]#?)(-?\d)$/.exec(nom);
  if (!m) throw new Error(`Note illisible : ${nom}`);
  const rang = DEMI_TONS[m[1]] + (Number(m[2]) + 1) * 12;
  return 440 * 2 ** ((rang - 69) / 12);
}

/* ── Les oscillateurs, à bande limitée ────────────────────────────────────
 *
 * Une onde carrée écrite naïvement — « +1 sur la première moitié, -1 sur la
 * seconde » — replie tout ce qui dépasse la moitié du taux d'échantillonnage
 * et rend un grésillement métallique. Sur un bruitage de vingt centièmes de
 * seconde cela passe pour du caractère ; sur quarante secondes de mélodie, cela
 * s'entend comme un défaut, et l'on rejetterait l'air pour une raison qui n'est
 * pas l'air.
 *
 * On somme donc les harmoniques une à une, en s'arrêtant avant le repli. C'est
 * plus cher à calculer et exact par construction.
 */

type Timbre = (frequence: number, phase: number) => number;

/** Combien d'harmoniques tiennent sous la moitié du taux. */
function partiels(frequence: number): number {
  return Math.max(1, Math.floor(TAUX / 2 / frequence) - 1);
}

/**
 * Une impulsion de rapport cyclique donné.
 *
 * Le terme continu `2d - 1` de la série est écarté : il ne s'entend pas et
 * décale toute la forme hors de zéro, ce qui mange de la marge et fait claquer
 * les débuts de note.
 */
function impulsion(rapport: number): Timbre {
  return (f, phase) => {
    let somme = 0;
    const n = partiels(f);
    for (let k = 1; k <= n; k++) {
      somme += (Math.sin(Math.PI * k * rapport) / k) * Math.cos(k * phase);
    }
    return (2 / Math.PI) * somme * 2;
  };
}

/** Une triangulaire : harmoniques impaires en 1/k², d'où sa douceur. */
const TRIANGLE: Timbre = (f, phase) => {
  let somme = 0;
  const n = partiels(f);
  for (let k = 1; k <= n; k += 2) {
    somme += ((((k - 1) / 2) % 2 === 0 ? 1 : -1) / (k * k)) * Math.sin(k * phase);
  }
  return (8 / Math.PI ** 2) * somme;
};

/* ── Les instruments ──────────────────────────────────────────────────── */

type Instrument = {
  timbre: Timbre;
  /** En secondes. La tenue est un niveau, non une durée. */
  attaque: number;
  chute: number;
  tenue: number;
  relache: number;
  /** Vitesse en Hz, profondeur en demi-tons. */
  vibrato?: { vitesse: number; profondeur: number; retard: number };
};

function amplitude(t: number, duree: number, i: Instrument): number {
  if (t < 0) return 0;
  if (t < i.attaque) return t / i.attaque;
  if (t < i.attaque + i.chute) {
    return 1 - (1 - i.tenue) * ((t - i.attaque) / i.chute);
  }
  if (t < duree) return i.tenue;
  const r = (t - duree) / i.relache;
  return r >= 1 ? 0 : i.tenue * (1 - r);
}

const MELODIE: Instrument = {
  timbre: impulsion(0.5),
  attaque: 0.012, chute: 0.09, tenue: 0.72, relache: 0.1,
  // Le vibrato n'entre qu'après un tiers de seconde : appliqué dès l'attaque,
  // il fait chevroter les notes courtes et la ligne perd son aplomb.
  vibrato: { vitesse: 5.2, profondeur: 0.13, retard: 0.34 },
};

const CONTRECHANT: Instrument = {
  timbre: impulsion(0.25),
  attaque: 0.006, chute: 0.05, tenue: 0.42, relache: 0.06,
};

const BASSE: Instrument = {
  timbre: TRIANGLE,
  attaque: 0.008, chute: 0.06, tenue: 0.8, relache: 0.09,
};

/* ── Le morceau ───────────────────────────────────────────────────────────
 *
 * « Le Château d'Émeraude » — ré mineur, 92 à la noire, seize mesures qui
 * bouclent.
 *
 * Ce qu'on cherche : une salle haute où il ne se passe rien de grave. Le
 * chapitre I,1 est « un matin où personne ne mourut », et le thème ne doit ni
 * sonner la charge ni pleurer. Le mineur porte l'attente — sept enfants sont
 * là pour une guerre dont personne ne sait le nom — et le septième degré
 * majeur de la huitième mesure (la accord de LA, avec son do dièse) ramène
 * vers le début sans jamais conclure. C'est ce qu'on veut d'une boucle : elle
 * ne doit pas se refermer, sinon on entend le raccord.
 */

type Accord = { basses: string[]; triade: string[] };

const ACCORDS: Record<string, Accord> = {
  Dm: { basses: ["D2", "A2", "D2", "F2"], triade: ["D4", "F4", "A4"] },
  Bb: { basses: ["A#1", "F2", "A#1", "D2"], triade: ["A#3", "D4", "F4"] },
  C: { basses: ["C2", "G2", "C2", "E2"], triade: ["C4", "E4", "G4"] },
  A: { basses: ["A1", "E2", "A1", "C#2"], triade: ["A3", "C#4", "E4"] },
  F: { basses: ["F1", "C2", "F1", "A1"], triade: ["F3", "A3", "C4"] },
  G: { basses: ["G1", "D2", "G1", "B1"], triade: ["G3", "B3", "D4"] },
};

/** La ligne de chant : par mesure, des couples note / durée en temps. */
type Evenement = [string | null, number];

type Morceau = {
  nom: string;
  tempo: number;
  /** Une mesure par entrée. */
  grille: string[];
  chant: Evenement[][];
  /** Combien de notes d'arpège par mesure : huit pour porter, quatre pour
   *  laisser respirer, zéro pour n'avoir que le chant et la basse. */
  arpege: number;
};

const CHANT_CHATEAU: Evenement[][] = [
  [["D5", 2], ["C5", 1], ["A4", 1]],
  [["A#4", 2], ["D5", 2]],
  [["C5", 2], ["A#4", 1], ["G4", 1]],
  [["A4", 3], [null, 1]],
  [["D5", 2], ["F5", 1], ["E5", 1]],
  [["D5", 2], ["A#4", 2]],
  [["C5", 1], ["D5", 1], ["E5", 2]],
  [["A4", 3], [null, 1]],

  [["F5", 2], ["E5", 1], ["D5", 1]],
  [["E5", 2], ["C5", 2]],
  [["D5", 1], ["B4", 1], ["G4", 2]],
  [["D5", 3], [null, 1]],
  [["F5", 2], ["D5", 1], ["A#4", 1]],
  [["C5", 2], ["A4", 2]],
  [["B4", 1], ["C5", 1], ["D5", 2]],
  [["A4", 2], [null, 2]],
];

/**
 * « Le Château d'Émeraude » — ré mineur, 92 à la noire, seize mesures.
 */
const CHATEAU: Morceau = {
  nom: "chateau-d-emeraude",
  tempo: 92,
  grille: [
    "Dm", "Bb", "C", "Dm", "Dm", "Bb", "C", "A",
    "F", "C", "G", "Dm", "Bb", "F", "G", "A",
  ],
  chant: CHANT_CHATEAU,
  arpege: 8,
};

/**
 * « L'écran-titre » — même ré mineur, mais 76 à la noire et huit mesures.
 *
 * Le titre ne raconte rien encore : il pose un monde. Plus lent, plus nu — un
 * arpège à la noire au lieu de la croche, et des notes tenues qui laissent la
 * salle sonner. Il reste dans la tonalité du Château pour que l'entrée dans le
 * jeu ne sonne pas comme un changement de monde.
 *
 * La huitième mesure tient sur LA majeur, comme au Château : la boucle ne se
 * referme jamais, sinon on entend le tour.
 */
const ECRAN_TITRE: Morceau = {
  nom: "ecran-titre",
  tempo: 76,
  grille: ["Dm", "Dm", "Bb", "C", "Dm", "Bb", "A", "A"],
  chant: [
    [["D5", 4]],
    [["A4", 2], ["D5", 2]],
    [["F5", 3], ["D5", 1]],
    [["E5", 4]],
    [["D5", 2], ["A4", 1], ["F4", 1]],
    [["D5", 4]],
    [["C#5", 2], ["E5", 2]],
    [["A4", 4]],
  ],
  arpege: 4,
};

const MORCEAUX: Morceau[] = [CHATEAU, ECRAN_TITRE];

const TEMPS_PAR_MESURE = 4;
/** Les notes se détachent : jouées un peu plus court que leur valeur, deux
 *  notes de même hauteur qui se suivent s'articulent au lieu de n'en faire
 *  qu'une longue. */
const DETACHE = 0.92;

type Voix = { instrument: Instrument; volume: number; evenements: Evenement[] };

function voix(m: Morceau): Voix[] {
  // L'arpège et la basse se déduisent de la grille : les écrire note à note
  // ferait un second exemplaire de l'harmonie, qui divergerait du premier à la
  // première retouche.
  const arpege: Evenement[] = [];
  const basse: Evenement[] = [];
  const MOTIF = [0, 1, 2, 1, 0, 1, 2, 1];
  for (const nom of m.grille) {
    const accord = ACCORDS[nom];
    if (m.arpege > 0) {
      const pas = 8 / m.arpege;
      for (let i = 0; i < m.arpege; i++) {
        arpege.push([accord.triade[MOTIF[Math.round(i * pas) % MOTIF.length]], (TEMPS_PAR_MESURE / m.arpege)]);
      }
    }
    for (const n of accord.basses) basse.push([n, 1]);
  }

  const voies: Voix[] = [
    { instrument: BASSE, volume: 0.42, evenements: basse },
    { instrument: MELODIE, volume: 0.5, evenements: m.chant.flat() },
  ];
  if (arpege.length) voies.splice(1, 0, { instrument: CONTRECHANT, volume: 0.17, evenements: arpege });
  return voies;
}

/* ── Le rendu ─────────────────────────────────────────────────────────── */

/**
 * Rend une voix dans un tampon.
 *
 * La phase se remet à zéro à chaque note : c'est ce que faisaient les puces
 * qu'on imite, et cela donne l'attaque nette qui les caractérise.
 */
function rendre(voix: Voix, parTemps: number, tampon: Float32Array): void {
  let temps = 0;
  for (const [nom, valeur] of voix.evenements) {
    const duree = valeur * parTemps;
    if (nom !== null) {
      const f = hz(nom);
      const tenue = duree * DETACHE;
      const fin = tenue + voix.instrument.relache;
      const depart = Math.round(temps * TAUX);
      let phase = 0;
      for (let i = 0; i < Math.ceil(fin * TAUX); i++) {
        const t = i / TAUX;
        const a = amplitude(t, tenue, voix.instrument);
        if (a > 0) {
          let hauteur = f;
          const v = voix.instrument.vibrato;
          if (v && t > v.retard) {
            hauteur *= 2 ** ((v.profondeur * Math.sin(2 * Math.PI * v.vitesse * (t - v.retard))) / 12);
          }
          phase += (2 * Math.PI * hauteur) / TAUX;
          // Le repli du tampon : ce qui déborde la fin du morceau revient au
          // début. C'est ce qui rend la boucle sans couture — voir plus bas.
          tampon[(depart + i) % tampon.length] += a * voix.volume * voix.instrument.timbre(hauteur, phase);
        } else {
          phase += (2 * Math.PI * f) / TAUX;
        }
      }
    }
    temps += duree;
  }
}

/**
 * Écrit la ou les musiques, et rend de quoi les vérifier.
 *
 * **La boucle est le seul point qu'une machine puisse juger ici.** Elle se
 * mesure : le morceau est rendu sur une longueur exacte en mesures, et la
 * traîne des dernières notes est repliée sur le début plutôt que coupée. Sans
 * ce repli, la dernière note s'arrête net au bouclage et l'on entend un clic
 * toutes les quarante secondes — le genre de défaut qu'on met une heure à
 * localiser parce qu'il est trop espacé pour qu'on l'attrape.
 *
 * Le reste — est-ce que l'air est bon — ne se mesure pas. Il s'écoute.
 */
export async function ecrireLesMusiques(
  dossier: string,
): Promise<{ nom: string; images: number; duree: number; pic: number; couture: number; octets: number }[]> {
  const fs = await import("node:fs");
  const path = await import("node:path");
  fs.mkdirSync(dossier, { recursive: true });

  return MORCEAUX.map((m) => {
    const parTemps = 60 / m.tempo;
    const total = m.grille.length * TEMPS_PAR_MESURE * parTemps;
    const tampon = new Float32Array(Math.round(total * TAUX));

    for (const v of voix(m)) rendre(v, parTemps, tampon);

    let pic = 0;
    for (const v of tampon) pic = Math.max(pic, Math.abs(v));
    if (pic > 0) {
      const g = 0.82 / pic;
      for (let i = 0; i < tampon.length; i++) tampon[i] *= g;
    }

    /* La couture : de combien le signal saute entre le dernier échantillon et
     * le premier. Sur un morceau bien replié elle doit rester du même ordre
     * qu'un écart entre deux échantillons voisins pris au hasard. */
    const couture = Math.abs(tampon[0] - tampon[tampon.length - 1]);
    const octets = wav(tampon);
    fs.writeFileSync(path.join(dossier, `${m.nom}.wav`), octets);

    return {
      nom: m.nom,
      // Le nombre d'images sert au moteur à poser la fin de boucle. Le lui
      // faire deviner depuis les octets marcherait tant que le fichier n'est
      // pas compressé à l'import, et cesserait de marcher le jour où il le sera.
      images: tampon.length,
      duree: tampon.length / TAUX,
      pic: 0.82,
      couture,
      octets: octets.length,
    };
  });
}
