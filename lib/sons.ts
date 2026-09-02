/**
 * Les bruitages, calculés.
 *
 * Même parti que les effets dessinés : un arc de taillade et une braise sont
 * des formes exactes, donc on les calcule. Un coup d'épée, une carapace qui
 * refuse un sort et un adversaire qui tombe le sont tout autant — ce sont des
 * enveloppes sur du bruit et quelques sinus.
 *
 * Rien n'est enregistré, rien n'est acheté, rien ne descend d'un service. Le
 * dépôt ne porte donc aucun fichier son dont on ne saurait dire d'où il vient,
 * ce qui est la même exigence que pour le reste : les romans ne quittent pas la
 * machine, et ce qu'on publie, on doit pouvoir en répondre.
 *
 * Le format est le plus bête qui soit — PCM 16 bits, mono, 22 050 Hz. Godot
 * l'importe sans réglage, et un son de combat n'a rien à gagner à davantage.
 */

export const TAUX = 22_050;

/** Un échantillonnage : la durée en secondes, et le tableau qui la porte. */
type Onde = Float32Array;

function toile(duree: number): Onde {
  return new Float32Array(Math.round(duree * TAUX));
}

/**
 * Un bruit reproductible.
 *
 * `Math.random` rendrait des fichiers différents à chaque production : le dépôt
 * verrait bouger huit binaires sans qu'un octet de code ait changé, et l'on ne
 * saurait plus lire un diff. La graine fixe rend la production idempotente —
 * même règle que pour les planches d'effets, qui se recalculent à l'identique.
 */
function graine(n: number): () => number {
  let e = (n >>> 0) || 1;
  return () => {
    e = (Math.imul(e, 1_664_525) + 1_013_904_223) >>> 0;
    return (e / 4_294_967_296) * 2 - 1;
  };
}

function bruit(duree: number, semence: number): Onde {
  const r = graine(semence);
  const x = toile(duree);
  for (let i = 0; i < x.length; i++) x[i] = r();
  return x;
}

/**
 * L'enveloppe : attaque courte, chute exponentielle, fin exactement à zéro.
 *
 * Le facteur `(1 - u)` n'est pas décoratif. Une exponentielle seule ne touche
 * jamais zéro : le fichier se termine sur un échantillon non nul, et la coupure
 * s'entend comme un clic — d'autant plus qu'un son de combat est court et joué
 * souvent.
 */
function enveloppe(t: number, duree: number, attaque = 0.005, courbe = 5): number {
  if (t >= duree) return 0;
  if (t < attaque) return t / attaque;
  const u = (t - attaque) / (duree - attaque);
  return Math.exp(-courbe * u) * (1 - u);
}

/** Un passe-bas à un pôle, dont la coupure peut bouger au cours du son. */
function passeBas(entree: Onde, coupure: (t: number) => number): Onde {
  const sortie = new Float32Array(entree.length);
  let y = 0;
  for (let i = 0; i < entree.length; i++) {
    const f = Math.min(Math.max(coupure(i / TAUX), 20), TAUX / 2 - 200);
    const a = 1 - Math.exp((-2 * Math.PI * f) / TAUX);
    y += a * (entree[i] - y);
    sortie[i] = y;
  }
  return sortie;
}

/** Un passe-haut, obtenu en ôtant les graves : ce qui reste est l'aigu. */
function passeHaut(entree: Onde, coupure: number): Onde {
  const graves = passeBas(entree, () => coupure);
  const sortie = new Float32Array(entree.length);
  for (let i = 0; i < entree.length; i++) sortie[i] = entree[i] - graves[i];
  return sortie;
}

/**
 * Un oscillateur dont la hauteur glisse.
 *
 * La phase s'accumule pas à pas au lieu de se calculer depuis `t` : autrement,
 * un balayage de fréquence casse la continuité de la phase et l'on entend un
 * craquement à chaque changement.
 */
function glissando(
  duree: number,
  hauteur: (t: number) => number,
  forme: (phase: number) => number = Math.sin,
): Onde {
  const x = toile(duree);
  let phase = 0;
  for (let i = 0; i < x.length; i++) {
    phase += (2 * Math.PI * hauteur(i / TAUX)) / TAUX;
    x[i] = forme(phase);
  }
  return x;
}

const CARRE = (p: number) => (Math.sin(p) >= 0 ? 1 : -1);

/**
 * Une impulsion de rapport cyclique, sans limitation de bande.
 *
 * Les musiques somment leurs harmoniques une à une pour éviter le grésillement
 * du repli ; sur un blip de cinq centièmes de seconde, ce repli n'a pas le
 * temps de s'entendre et fait même partie du grain qu'on cherche.
 */
function impulsionSimple(rapport: number) {
  return (p: number) => (((p / (2 * Math.PI)) % 1) < rapport ? 1 : -1);
}

function melanger(...voix: Onde[]): Onde {
  const n = Math.max(...voix.map((v) => v.length));
  const x = new Float32Array(n);
  for (const v of voix) for (let i = 0; i < v.length; i++) x[i] += v[i];
  return x;
}

function appliquer(x: Onde, forme: (t: number) => number): Onde {
  const y = new Float32Array(x.length);
  for (let i = 0; i < x.length; i++) y[i] = x[i] * forme(i / TAUX);
  return y;
}

/**
 * Ramène le sommet à une cible commune.
 *
 * Chaque son est normalisé, puis pondéré une fois pour toutes ici. Régler les
 * volumes du côté de Godot obligerait à tenir un second barème, et deux barèmes
 * ne s'accordent pas longtemps.
 */
function normaliser(x: Onde, cible: number): Onde {
  let sommet = 0;
  for (const v of x) sommet = Math.max(sommet, Math.abs(v));
  if (sommet < 1e-9) return x;
  const g = cible / sommet;
  for (let i = 0; i < x.length; i++) x[i] *= g;
  return x;
}

/** Le seul écrivain de WAV du dépôt : les musiques passent par ici aussi. */
export function wav(x: Float32Array): Buffer {
  const corps = Buffer.alloc(x.length * 2);
  for (let i = 0; i < x.length; i++) {
    const v = Math.min(Math.max(x[i], -1), 1);
    corps.writeInt16LE(Math.round(v * 32_767), i * 2);
  }
  const tete = Buffer.alloc(44);
  tete.write("RIFF", 0);
  tete.writeUInt32LE(36 + corps.length, 4);
  tete.write("WAVE", 8);
  tete.write("fmt ", 12);
  tete.writeUInt32LE(16, 16);
  tete.writeUInt16LE(1, 20); // PCM
  tete.writeUInt16LE(1, 22); // mono
  tete.writeUInt32LE(TAUX, 24);
  tete.writeUInt32LE(TAUX * 2, 28); // octets par seconde
  tete.writeUInt16LE(2, 32); // octets par trame
  tete.writeUInt16LE(16, 34);
  tete.write("data", 36);
  tete.writeUInt32LE(corps.length, 40);
  return Buffer.concat([tete, corps]);
}

/* ── Les huit bruitages ────────────────────────────────────────────────────
 *
 * Ce qu'ils doivent faire entendre, et pourquoi c'est celui-là :
 *
 * Le fer et la magie sont deux registres imposés par le texte — la carapace des
 * hommes-insectes « les rend invulnérables à la magie ». On voit déjà qu'un
 * sort ne prend pas : il poursuit sa course au lieu de s'éteindre. Il faut
 * aussi qu'on l'entende, et que ce son-là ne ressemble à aucun autre : c'est
 * une règle du récit, pas un raté d'affichage.
 */

type Recette = { nom: string; faire: () => Onde };

const RECETTES: Recette[] = [
  {
    // Le fer fend l'air. Coupure descendante : du sifflement au souffle, ce que
    // fait une lame qui ralentit. Aucune hauteur définie — un geste n'a pas de
    // note, et lui en donner une le rend comique.
    nom: "epee",
    faire: () => {
      const d = 0.2;
      const souffle = passeHaut(passeBas(bruit(d, 1), (t) => 7200 * Math.exp(-10 * t) + 620), 380);
      return normaliser(appliquer(souffle, (t) => enveloppe(t, d, 0.004, 6)), 0.62);
    },
  },
  {
    // La lame entre. Un choc mat : une basse qui tombe vite, et juste assez de
    // bruit sourd pour que ce ne soit pas une note de musique.
    nom: "fer-touche",
    faire: () => {
      const d = 0.16;
      const choc = appliquer(
        glissando(d, (t) => 150 * Math.exp(-22 * t) + 62),
        (t) => enveloppe(t, d, 0.002, 9),
      );
      const chair = appliquer(
        passeBas(bruit(d, 2), (t) => 2600 * Math.exp(-30 * t) + 300),
        (t) => enveloppe(t, d, 0.001, 14),
      );
      return normaliser(melanger(appliquer(choc, () => 0.9), appliquer(chair, () => 0.6)), 0.8);
    },
  },
  {
    // Le feu de Theandras part. La coupure monte puis retombe : un embrasement
    // s'ouvre avant de s'emporter. Une dent de scie grave par-dessous lui donne
    // le corps qu'un bruit seul n'a pas.
    nom: "sort",
    faire: () => {
      const d = 0.3;
      const flamme = passeBas(bruit(d, 3), (t) => 400 + 5200 * Math.sin(Math.min(t / d, 1) * Math.PI));
      const corps = appliquer(
        glissando(d, (t) => 90 + 210 * t, (p) => ((p / Math.PI) % 2) - 1),
        (t) => enveloppe(t, d, 0.02, 4),
      );
      return normaliser(
        melanger(appliquer(flamme, (t) => enveloppe(t, d, 0.03, 3)), appliquer(corps, () => 0.45)),
        0.7,
      );
    },
  },
  {
    // Le feu prend. Plus bref et plus large que le départ : une déflagration,
    // suivie d'une traîne qui descend.
    nom: "sort-touche",
    faire: () => {
      const d = 0.32;
      const eclat = appliquer(
        passeBas(bruit(d, 4), (t) => 5200 * Math.exp(-7 * t) + 260),
        (t) => enveloppe(t, d, 0.002, 5),
      );
      const fond = appliquer(
        glissando(d, (t) => 220 * Math.exp(-6 * t) + 55),
        (t) => enveloppe(t, d, 0.004, 6),
      );
      return normaliser(melanger(eclat, appliquer(fond, () => 0.7)), 0.85);
    },
  },
  {
    // La carapace refuse. Deux partiels volontairement faux l'un avec l'autre —
    // un rapport de 1,51, qui ne tombe sur aucun intervalle — et une chute très
    // rapide : cela sonne le métal, non la chair. C'est le seul son du jeu qui
    // dise « ça n'a pas pris », et il ne doit ressembler à aucun autre.
    nom: "sort-glisse",
    faire: () => {
      const d = 0.26;
      const a = appliquer(glissando(d, () => 2_090), (t) => enveloppe(t, d, 0.001, 11));
      const b = appliquer(glissando(d, () => 3_156), (t) => enveloppe(t, d, 0.001, 16));
      const raclure = appliquer(passeHaut(bruit(d, 5), 3_400), (t) => enveloppe(t, d, 0.001, 26));
      return normaliser(
        melanger(a, appliquer(b, () => 0.55), appliquer(raclure, () => 0.5)),
        0.55,
      );
    },
  },
  {
    // L'adversaire touche Wellan. Plus court, plus haut et plus sec que le
    // coup d'épée : ce n'est pas la même arme, et le joueur doit savoir sans
    // regarder lequel des deux vient de porter.
    nom: "griffe",
    faire: () => {
      const d = 0.11;
      const sec = appliquer(
        passeHaut(passeBas(bruit(d, 6), (t) => 6_400 * Math.exp(-26 * t) + 900), 900),
        (t) => enveloppe(t, d, 0.001, 16),
      );
      const sourd = appliquer(
        glissando(d, (t) => 260 * Math.exp(-30 * t) + 90),
        (t) => enveloppe(t, d, 0.001, 18),
      );
      return normaliser(melanger(sec, appliquer(sourd, () => 0.55)), 0.75);
    },
  },
  {
    // L'adversaire tombe. Une hauteur qui s'effondre : le seul son du jeu qui
    // descende aussi loin, pour qu'une mort ne se confonde pas avec un coup.
    nom: "ennemi-meurt",
    faire: () => {
      const d = 0.36;
      const cri = appliquer(
        glissando(d, (t) => 430 * Math.exp(-7.5 * t) + 58, CARRE),
        (t) => enveloppe(t, d, 0.004, 4.5),
      );
      const rale = appliquer(
        passeBas(bruit(d, 7), (t) => 1_900 * Math.exp(-5 * t) + 180),
        (t) => enveloppe(t, d, 0.01, 3.5),
      );
      return normaliser(melanger(appliquer(cri, () => 0.55), appliquer(rale, () => 0.7)), 0.7);
    },
  },
  {
    // Une page de dialogue paraît.
    //
    // C'est le son le plus joué du jeu — une conversation en compte dix — donc
    // le plus court et le plus discret. Un blip trop marqué devient une gêne au
    // bout de trois répliques, et l'on coupe le son pour lire tranquille.
    nom: "parole",
    faire: () => {
      const d = 0.05;
      const voix = appliquer(
        glissando(d, (t) => 760 + 180 * Math.exp(-40 * t), impulsionSimple(0.3)),
        (t) => enveloppe(t, d, 0.002, 12),
      );
      return normaliser(voix, 0.3);
    },
  },
  {
    // Le curseur change d'entrée. Plus haut et plus bref que la parole : ce
    // n'est pas quelqu'un qui parle, c'est une mécanique qui répond.
    nom: "menu-deplace",
    faire: () => {
      const d = 0.035;
      return normaliser(
        appliquer(glissando(d, () => 1_180, impulsionSimple(0.5)),
          (t) => enveloppe(t, d, 0.001, 14)),
        0.28,
      );
    },
  },
  {
    // Une entrée est choisie. Deux hauteurs qui montent : rien d'autre dans le
    // jeu ne monte, et c'est ce qui distingue « validé » de « déplacé ».
    nom: "menu-choix",
    faire: () => {
      const d = 0.17;
      const bas = appliquer(glissando(0.06, () => 784, impulsionSimple(0.5)),
        (t) => enveloppe(t, 0.06, 0.002, 10));
      const haut = appliquer(glissando(d, () => 1_175, impulsionSimple(0.5)),
        (t) => (t < 0.055 ? 0 : enveloppe(t - 0.055, d - 0.055, 0.002, 8)));
      return normaliser(melanger(bas, haut), 0.4);
    },
  },
  {
    // Une fiche entre au Codex. Trois notes qui montent, douces : c'est un gain,
    // et rien d'autre dans le jeu ne monte trois fois. Le son de menu aurait
    // fait sonner une rencontre comme la validation d'une entrée de liste.
    nom: "codex-ajout",
    faire: () => {
      const d = 0.42;
      const notes = [[587.33, 0.0], [783.99, 0.09], [1174.66, 0.18]];
      const voix = notes.map(([f, retard]) =>
        appliquer(glissando(d, () => f, impulsionSimple(0.5)), (t) =>
          t < retard ? 0 : enveloppe(t - retard, d - retard, 0.004, 5) * 0.6));
      return normaliser(melanger(...voix), 0.38);
    },
  },
  {
    // Wellan tombe. Le plus long et le plus grave : la partie s'arrête, et rien
    // d'autre dans le jeu ne dure autant.
    nom: "wellan-tombe",
    faire: () => {
      const d = 0.62;
      const chute = appliquer(
        glissando(d, (t) => 205 * Math.exp(-4.2 * t) + 42),
        (t) => enveloppe(t, d, 0.008, 3),
      );
      const masse = appliquer(
        passeBas(bruit(d, 8), (t) => 900 * Math.exp(-4 * t) + 110),
        (t) => enveloppe(t, d, 0.004, 3.2),
      );
      return normaliser(melanger(chute, appliquer(masse, () => 0.5)), 0.85);
    },
  },
];

/** Les noms, dans l'ordre. Le moteur les lit dans `monde.json`. */
export const SONS: string[] = RECETTES.map((r) => r.nom);

/**
 * Écrit les huit fichiers et rend ce qu'ils durent.
 *
 * On rend les durées parce qu'un son ne se regarde pas. Une planche fausse se
 * voit sur une capture ; un fichier son vide, tronqué ou muet ne se voit nulle
 * part. La durée mesurée à la production est la seule trace qu'on ait avant
 * d'écouter.
 */
export async function ecrireLesSons(
  dossier: string,
): Promise<{ nom: string; duree: number; octets: number; pic: number; fin: number }[]> {
  const fs = await import("node:fs");
  const path = await import("node:path");
  fs.mkdirSync(dossier, { recursive: true });

  return RECETTES.map(({ nom, faire }) => {
    const onde = faire();
    const octets = wav(onde);
    fs.writeFileSync(path.join(dossier, `${nom}.wav`), octets);

    /* Le sommet et le dernier échantillon, relevés sur ce qu'on vient d'écrire.
     *
     * Un fichier de la bonne taille mais plein de zéros a exactement l'air d'un
     * fichier correct : même durée, même en-tête, même poids à l'octet près.
     * C'est la dégradation silencieuse habituelle, et c'est pire pour un son
     * que pour une image — on ne peut même pas la regarder. Le dernier
     * échantillon dit l'autre défaut qui ne se voit pas davantage : une
     * enveloppe qui ne retombe pas à zéro fait claquer la coupure. */
    let pic = 0;
    for (const v of onde) pic = Math.max(pic, Math.abs(v));
    const fin = onde.length ? Math.abs(onde[onde.length - 1]) : 0;
    return { nom, duree: onde.length / TAUX, octets: octets.length, pic, fin };
  });
}
