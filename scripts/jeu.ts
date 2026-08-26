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
 *   npm run jeu -- --scene i-01   joue un chapitre précis
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

/** Les planches dont la scène a besoin, et d'où elles viennent. */
const REQUIS = [
  { de: path.join(ART, "personnages", "wellan.png"), vers: "wellan.png", quoi: "Wellan" },
  { de: path.join(ART, "lieux", "chateau-d-emeraude.png"), vers: "chateau-d-emeraude.png", quoi: "le sol du Château" },
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

function main() {
  const manquant = REQUIS.filter((r) => !fs.existsSync(r.de));
  if (manquant.length) {
    console.error(`${C.red}Planche(s) absente(s) :${C.off}`);
    for (const m of manquant) console.error(`  ${m.quoi} — ${path.relative(ROOT, m.de)}`);
    console.error("\n  npm run art:normalise      les assemble depuis jeu/art/sources/");
    process.exit(1);
  }

  fs.mkdirSync(ASSETS, { recursive: true });
  for (const r of REQUIS) fs.copyFileSync(r.de, path.join(ASSETS, r.vers));
  console.log(`${C.dim}${REQUIS.length} planche(s) copiée(s) dans ${path.relative(ROOT, ASSETS)}/${C.off}`);

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
