/**
 * Lance le jeu.
 *
 * Les planches vivent dans jeu/art/, produites par l'atelier graphique ; le
 * projet Godot vit dans jeu/godot/. On les copie plutôt que de les partager :
 * un projet Godot importe tout ce qu'il trouve sous sa racine, et l'ouvrir sur
 * jeu/art/ lui ferait avaler les centaines d'images brutes de sources/.
 *
 * Usage :
 *   npm run jeu
 *   npm run jeu -- --scene i-01   joue un chapitre précis, sans toucher à la partie
 *   npm run jeu -- --recommencer  efface la progression et reprend au premier chapitre
 *   npm run jeu -- --editeur      ouvre l'éditeur au lieu de jouer
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

const ROOT = path.resolve(import.meta.dirname, "..");
const ART = path.join(ROOT, "jeu", "art");
const PROJET = path.join(ROOT, "jeu", "godot");
const ASSETS = path.join(PROJET, "assets");

const C = { red: "\x1b[31m", green: "\x1b[32m", dim: "\x1b[2m", off: "\x1b[0m" };

/**
 * Tout ce que l'atelier a produit part dans le projet Godot.
 *
 * La liste était nommée à la main et n'a pas suivi : elle ne portait encore que
 * Wellan et le Château alors que six personnages et quatre terrains existaient.
 * Le jeu se lançait donc sans Kira, sans la Reine, sans les ennemis ni la neige
 * de Shola — et rien ne le signalait, puisqu'un personnage sans planche paraît
 * en silhouette, ce qui est un comportement prévu.
 *
 * On copie donc le dossier, non une liste. Ce qui existe part ; ce qui manque
 * se voit à l'arrivée.
 */
function planches(): { de: string; vers: string }[] {
  const out: { de: string; vers: string }[] = [];
  for (const sous of ["personnages", "lieux"]) {
    const dir = path.join(ART, sous);
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (f.endsWith(".png")) out.push({ de: path.join(dir, f), vers: f });
    }
  }
  return out;
}

/** Sans celles-ci, la première scène s'ouvre sur du vide. */
const INDISPENSABLES = [
  { fichier: "wellan.png", quoi: "Wellan" },
  { fichier: "chateau-d-emeraude.png", quoi: "le sol du Château" },
];

function godot(): string {
  for (const candidat of ["godot", "/opt/homebrew/bin/godot", "/usr/local/bin/godot",
                          "/Applications/Godot.app/Contents/MacOS/Godot"]) {
    const r = spawnSync(candidat, ["--version"], { encoding: "utf8" });
    if (r.status === 0) return candidat;
  }
  console.error(`${C.red}Godot introuvable.${C.off}`);
  console.error("  brew install godot   ou   https://godotengine.org/download");
  process.exit(1);
}

/**
 * Dit où l'on reprend, avant que la fenêtre s'ouvre.
 *
 * Sans cela, on lance le jeu sans savoir à quel chapitre il va nous déposer —
 * et l'on ne s'aperçoit qu'une partie a été poussée trop loin qu'une fois
 * devant une bataille qu'on n'a pas méritée.
 */
function annoncerLaReprise() {
  const base = path.join(process.env.HOME ?? "", "Library", "Application Support", "Godot", "app_userdata");
  let carnet = "";
  const fouiller = (d: string) => {
    if (!fs.existsSync(d)) return;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) fouiller(p);
      else if (e.name === "progression.json") carnet = p;
    }
  };
  fouiller(base);

  const donnees = path.join(PROJET, "donnees");
  const campagne = JSON.parse(fs.readFileSync(path.join(donnees, "campagne.json"), "utf8"));
  const suite: string[] = campagne.chapitres ?? [];
  const repris = carnet ? JSON.parse(fs.readFileSync(carnet, "utf8")).chapitre : suite[0];
  const rang = suite.indexOf(repris) + 1;
  if (rang < 1) return;

  const scene = JSON.parse(fs.readFileSync(path.join(donnees, "scenes", `${repris}.json`), "utf8"));
  console.log(`${C.dim}chapitre ${rang} sur ${suite.length} — ${scene.titre}${C.off}`);
  if (rang > 1) console.log(`${C.dim}pour reprendre au début : npm run jeu -- --recommencer${C.off}`);
}

function main() {
  const tout = planches();
  const noms = new Set(tout.map((p) => p.vers));
  const manquant = INDISPENSABLES.filter((i) => !noms.has(i.fichier));
  if (manquant.length) {
    console.error(`${C.red}Planche(s) absente(s) :${C.off}`);
    for (const m of manquant) console.error(`  ${m.quoi} — jeu/art/**/${m.fichier}`);
    console.error("\n  npm run art:normalise      les assemble depuis jeu/art/sources/");
    process.exit(1);
  }

  fs.mkdirSync(ASSETS, { recursive: true });
  for (const p of tout) fs.copyFileSync(p.de, path.join(ASSETS, p.vers));
  console.log(`${C.dim}${tout.length} planche(s) copiée(s) dans ${path.relative(ROOT, ASSETS)}/${C.off}`);

  if (process.argv.includes("--recommencer")) {
    /* La progression vit dans le dossier utilisateur de Godot, sous le nom du
     * projet. On la cherche plutôt que de la calculer : le chemin dépend de la
     * plateforme, et une mauvaise devinette effacerait le mauvais fichier. */
    const base = path.join(process.env.HOME ?? "", "Library", "Application Support", "Godot", "app_userdata");
    let efface = 0;
    const fouiller = (d: string) => {
      if (!fs.existsSync(d)) return;
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) fouiller(p);
        else if (e.name === "progression.json") { fs.unlinkSync(p); efface++; }
      }
    };
    fouiller(base);
    console.log(`${C.dim}${efface ? "progression effacée" : "aucune partie en cours"}${C.off}`);
  }

  annoncerLaReprise();

  const bin = godot();
  const version = spawnSync(bin, ["--version"], { encoding: "utf8" }).stdout.trim();
  console.log(`${C.dim}${version}${C.off}`);

  /* L'import doit précéder le lancement : sans lui, Godot démarre avant d'avoir
   * lu les PNG et la scène s'ouvre sans ses textures. */
  try {
    execFileSync(bin, ["--headless", "--path", PROJET, "--import"], { stdio: "pipe", timeout: 120_000 });
  } catch {
    // L'import signale parfois des avertissements en sortie d'erreur sans avoir échoué.
  }

  if (process.argv.includes("--editeur")) {
    spawnSync(bin, ["--path", PROJET, "--editor"], { stdio: "inherit" });
    return;
  }

  /*
   * Les arguments de scène passent au moteur, après `++`.
   *
   * Avant `++`, Godot les revendique : un mot sans tiret y est pris pour un
   * chemin de scène à charger, et le jeu refuse de démarrer sur « i-01 ».
   */
  const passe: string[] = [];
  const i = process.argv.indexOf("--scene");
  if (i >= 0 && process.argv[i + 1]) passe.push("++", "--scene", process.argv[i + 1]);

  console.log(`${C.green}Le jeu démarre.${C.off} Flèches pour marcher, Espace pour parler, J l'épée, K le feu.`);
  const r = spawnSync(bin, ["--path", PROJET, ...passe], { stdio: "inherit" });
  process.exitCode = r.status ?? 0;
}

main();
