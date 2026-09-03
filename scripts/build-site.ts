/**
 * Construit le site statique du Codex pour GitHub Pages.
 *
 *   fiches JSON  →  écartement des routes serveur  →  next build (export)
 *                →  contrôle anti-secret  →  out/
 *
 * Les routes serveur doivent disparaître le temps du build : `output: "export"`
 * les refuse, et elles n'ont de toute façon aucun sens sur un hébergeur
 * statique. Elles sont remises en place quoi qu'il arrive.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const ROOT = path.resolve(import.meta.dirname, "..");
const API = path.join(ROOT, "app", "api");
// Hors de `app/` : un dossier qui y reste est vu comme une route, quel que
// soit son nom — un point en tête n'y change rien.
const PARKED = path.join(ROOT, ".api.parked");
const OUT = path.join(ROOT, "out");

const run = (cmd: string, args: string[], env: Record<string, string> = {}) =>
  execFileSync(cmd, args, { cwd: ROOT, stdio: "inherit", env: { ...process.env, ...env } });

/** Motifs de secrets qui ne doivent jamais atteindre un fichier publié. */
const SECRETS: [RegExp, string][] = [
  [/sk-ant-[A-Za-z0-9_-]{20,}/, "clé API Anthropic"],
  [/gh[pousr]_[A-Za-z0-9]{30,}/, "jeton GitHub"],
];

function scanForSecrets(dir: string): string[] {
  const found: string[] = [];
  const walk = (d: string) => {
    for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, entry.name);
      if (entry.isDirectory()) { walk(p); continue; }
      let body: string;
      try { body = fs.readFileSync(p, "utf8"); } catch { continue; }
      for (const [re, label] of SECRETS) {
        if (re.test(body)) found.push(`${path.relative(OUT, p)} — ${label}`);
      }
    }
  };
  walk(dir);
  return found;
}

function main() {
  // Une exécution précédente interrompue a pu laisser les routes de côté.
  if (fs.existsSync(PARKED) && !fs.existsSync(API)) {
    fs.renameSync(PARKED, API);
    console.log("Routes serveur restaurées après une exécution interrompue.\n");
  }

  /*
   * Le jeu doit être là avant qu'on construise quoi que ce soit.
   *
   * `public/jeu/` n'est pas versionné — quarante mégaoctets de WebAssembly
   * reconstruits à la demande. Publier sans lui aurait donné un site complet
   * dont l'onglet « Jeu » sert une page blanche : exactement la dégradation
   * qui ne se voit qu'une fois en ligne. On refuse ici, en nommant le remède.
   */
  const jeu = path.join(ROOT, "public", "jeu");
  const piecesDuJeu = ["index.html", "index.js", "index.wasm", "index.pck"];
  const sansJeu = piecesDuJeu.filter((f) => !fs.existsSync(path.join(jeu, f)));
  if (sansJeu.length) {
    console.error("PUBLICATION REFUSÉE — l'export web du jeu est absent ou incomplet.");
    console.error(`  manque : ${sansJeu.join(", ")}`);
    console.error("\n  npm run jeu:web      le reconstruit (environ une minute)");
    process.exit(1);
  }

  console.log("→ Génération des fiches\n");
  run("npx", ["tsx", "scripts/build-pages.ts"]);

  console.log("\n→ Export statique\n");
  fs.rmSync(OUT, { recursive: true, force: true });
  const hadApi = fs.existsSync(API);
  if (hadApi) fs.renameSync(API, PARKED);
  try {
    run("npx", ["next", "build"], { PAGES: "1" });
  } finally {
    if (hadApi && fs.existsSync(PARKED)) fs.renameSync(PARKED, API);
  }

  if (!fs.existsSync(OUT)) {
    console.error("\nAucune sortie dans out/ — build interrompu.");
    process.exit(1);
  }

  // Sans ce marqueur, GitHub Pages passe le site à Jekyll, qui ignore tout
  // dossier commençant par « _ » — donc `_next/`, c'est-à-dire le site entier.
  fs.writeFileSync(path.join(OUT, ".nojekyll"), "");

  console.log("\n→ Contrôle du contenu publié\n");
  const leaks = scanForSecrets(OUT);
  if (leaks.length) {
    console.error("PUBLICATION REFUSÉE — des secrets figurent dans la sortie :");
    for (const l of leaks) console.error(`  ${l}`);
    process.exit(1);
  }

  // Le texte des romans ne doit jamais partir : seul le Codex est publié.
  const forbidden = ["chunks.json", "bm25.json", "embeddings.bin"];
  const present = forbidden.filter((f) => fs.existsSync(path.join(OUT, f)));
  if (present.length) {
    console.error(`PUBLICATION REFUSÉE — index de recherche présent : ${present.join(", ")}`);
    process.exit(1);
  }

  const size = execFileSync("du", ["-sh", OUT]).toString().split("\t")[0];
  const files = execFileSync("bash", ["-c", `find ${JSON.stringify(OUT)} -type f | wc -l`]).toString().trim();
  const jeuPublie = piecesDuJeu.filter((f) => !fs.existsSync(path.join(OUT, "jeu", f)));
  if (jeuPublie.length) {
    console.error(`PUBLICATION REFUSÉE — le jeu n'a pas suivi dans out/ : ${jeuPublie.join(", ")}`);
    process.exit(1);
  }

  console.log(`  aucun secret, aucun index de recherche`);
  console.log(`  le jeu est du voyage`);
  console.log(`  ${files} fichiers · ${size}`);
  console.log(`\nSite prêt dans out/. Publication : npm run deploy`);
}

main();
