/**
 * Contrôle un chapitre, ou tous, sans ouvrir de fenêtre.
 *
 * Le parcours complet — `npm run jeu -- --capture` — éprouve le tour du
 * Château, la musique, la course, le sac, les commandes, les orientations, la
 * pause. C'est ce qu'on veut avant de livrer. C'est ruineux quand on écrit un
 * chapitre : vingt-six secondes et une fenêtre pour savoir si l'on a oublié de
 * poser Élund dans sa tour.
 *
 * Celui-ci ne répond qu'à une question par chapitre — se joue-t-il jusqu'au
 * bout, et qu'est-ce qui manque ? — en six secondes et sans écran. La suite des
 * dix-huit tient en deux minutes au lieu de dix.
 *
 * Usage :
 *   npm run jeu:chapitres              tous les chapitres de la campagne
 *   npm run jeu:chapitres -- i-23      celui-là seulement
 *   npm run jeu:chapitres -- i-20 i-23 ceux-là
 *
 * Ce qu'il ne fait pas : regarder. Aucune image n'est saisie, donc rien ici ne
 * dira qu'un roi est décapité ou qu'une réplique déborde de son cadre. Pour
 * cela, le parcours complet reste le seul juge.
 */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = path.resolve(import.meta.dirname, "..");
const PROJET = path.join(ROOT, "jeu", "godot");
const C = { red: "\x1b[31m", yellow: "\x1b[33m", green: "\x1b[32m", dim: "\x1b[2m", off: "\x1b[0m" };

function godot(): string {
  for (const candidat of ["godot", "/opt/homebrew/bin/godot", "/usr/local/bin/godot",
                          "/Applications/Godot.app/Contents/MacOS/Godot"]) {
    if (spawnSync(candidat, ["--version"], { encoding: "utf8" }).status === 0) return candidat;
  }
  console.error(`${C.red}Godot introuvable.${C.off}  brew install godot`);
  process.exit(1);
}

type Bilan = {
  id: string; acheve: boolean; etapes: number; absents: string;
  reste: number; duree: string; erreurs: string[];
};

/**
 * Relève d'un chapitre.
 *
 * On lit la ligne `RAPIDE` que le banc imprime, et **aussi** les erreurs de
 * script que Godot crache sur sa sortie d'erreur : un chapitre peut s'achever
 * tout en laissant une fiche inconnue ou une planche absente derrière lui, et
 * ce sont précisément les avertissements qu'on ne voit jamais quand on joue.
 */
function jouer(bin: string, id: string): Bilan {
  const r = spawnSync(bin, ["--headless", "--path", PROJET, "++", "--scene", id, "--verifier",
                            "--quit-after", "60000"], { encoding: "utf8", timeout: 120_000 });
  const sortie = `${r.stdout ?? ""}\n${r.stderr ?? ""}`;
  const ligne = sortie.split("\n").find((l) => l.startsWith("RAPIDE ")) ?? "";
  const champ = (nom: string) => (new RegExp(`${nom}=([^ |]+)`).exec(ligne)?.[1] ?? "");

  const erreurs = [...new Set(
    sortie.split("\n")
      .filter((l) => /SCRIPT ERROR|Fiche inconnue|introuvable|Sorte de mobilier inconnue|Musique introuvable|Bruitage introuvable|Porte vers une salle inconnue|Salle inconnue|hors des bords/.test(l))
      .map((l) => l.replace(/^\s*(ERROR|WARNING):\s*/, "").trim().slice(0, 110)),
  )];

  return {
    id,
    acheve: ligne.includes("| achevé |"),
    etapes: Number(champ("etapes") || 0),
    absents: champ("absents") || (ligne ? "aucun" : "—"),
    reste: Number(champ("reste") || 0),
    duree: /\| ([\d.]+)s$/.exec(ligne.trim())?.[1] ?? "?",
    erreurs,
  };
}

function main() {
  const demandes = process.argv.slice(2).filter((a) => !a.startsWith("-"));
  const campagne = JSON.parse(
    fs.readFileSync(path.join(PROJET, "donnees", "campagne.json"), "utf8"),
  ).chapitres as string[];

  const inconnus = demandes.filter((d) => !campagne.includes(d));
  if (inconnus.length) {
    console.error(`${C.red}Chapitre inconnu : ${inconnus.join(", ")}${C.off}`);
    console.error(`${C.dim}La campagne porte : ${campagne.join(", ")}${C.off}`);
    process.exit(1);
  }

  const liste = demandes.length ? demandes : campagne;
  const bin = godot();
  console.log(`${C.dim}${liste.length} chapitre(s), sans fenêtre${C.off}\n`);

  const bilans: Bilan[] = [];
  for (const id of liste) {
    const b = jouer(bin, id);
    bilans.push(b);
    const marque = b.acheve && !b.erreurs.length ? `${C.green}✓${C.off}`
      : b.acheve ? `${C.yellow}!${C.off}` : `${C.red}✗${C.off}`;
    console.log(`${marque} ${id.padEnd(6)} ${(b.acheve ? "achevé" : "PAS ACHEVÉ").padEnd(11)}`
      + `${String(b.etapes).padStart(2)} étape(s)   `
      + `${b.absents === "aucun" ? C.dim + "personne d'absent" + C.off : C.red + "absents : " + b.absents + C.off}`
      + `   ${C.dim}${b.reste} à dire après clôture · ${b.duree}s${C.off}`);
    for (const e of b.erreurs) console.log(`    ${C.red}${e}${C.off}`);
  }

  const casses = bilans.filter((b) => !b.acheve || b.erreurs.length);
  /* Un chapitre où personne n'a plus rien à dire après la clôture n'est pas
   * cassé, mais il n'a que le strict nécessaire : toutes les répliques y sont
   * exigées par un objectif, et il n'y a rien à rattraper en traînant. */
  const maigres = bilans.filter((b) => b.acheve && b.reste === 0);

  console.log();
  if (maigres.length) {
    console.log(`${C.yellow}${maigres.length} chapitre(s) sans rien à rattraper après la clôture : `
      + `${maigres.map((b) => b.id).join(", ")}${C.off}`);
  }
  console.log(casses.length
    ? `${C.red}${casses.length} chapitre(s) à reprendre : ${casses.map((b) => b.id).join(", ")}${C.off}`
    : `${C.green}${bilans.length} chapitre(s) se jouent jusqu'au bout.${C.off}`);
  process.exitCode = casses.length ? 1 : 0;
}

main();
