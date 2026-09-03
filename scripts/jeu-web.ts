/**
 * Exporte le jeu pour le navigateur.
 *
 * Godot rend un WebAssembly que la page embarque dans une iframe. Deux choix
 * comptent, tous deux inscrits dans `jeu/godot/export_presets.cfg` :
 *
 * `variant/thread_support=false` — sans fils d'exécution. Un export avec fils
 * réclame `SharedArrayBuffer`, donc les en-têtes `Cross-Origin-Opener-Policy`
 * et `Cross-Origin-Embedder-Policy`. GitHub Pages sert des fichiers et ne pose
 * aucun en-tête : le jeu s'y serait chargé puis planté sur un message que
 * personne n'aurait su lire.
 *
 * `gl_compatibility` — déjà le rendu du projet, et le seul que le web accepte.
 * C'est la raison pour laquelle ce portage n'a rien coûté au jeu lui-même.
 *
 * Usage :
 *   npm run jeu:web
 */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { godot, preparerLesPlanches } from "./jeu.ts";

const ROOT = path.resolve(import.meta.dirname, "..");
const PROJET = path.join(ROOT, "jeu", "godot");
const SORTIE = path.join(ROOT, "public", "jeu");

const C = { red: "\x1b[31m", green: "\x1b[32m", dim: "\x1b[2m", off: "\x1b[0m" };

/** Ce qu'un export réussi laisse toujours derrière lui. */
const ATTENDUS = ["index.html", "index.js", "index.wasm", "index.pck"];

function main() {
  preparerLesPlanches();

  const bin = godot();

  /*
   * On exporte à côté, puis on remplace.
   *
   * Godot écrit ses fichiers un par un : un export interrompu au milieu
   * laisserait un `public/jeu/` mi-ancien mi-neuf, que la publication
   * emporterait sans rien remarquer. Le dossier définitif n'est touché
   * qu'une fois l'export entier vérifié.
   */
  const chantier = path.join(ROOT, "public", ".jeu.chantier");
  fs.rmSync(chantier, { recursive: true, force: true });
  fs.mkdirSync(chantier, { recursive: true });

  const cible = path.relative(PROJET, path.join(chantier, "index.html"));
  console.log(`${C.dim}export web depuis ${path.relative(ROOT, PROJET)}/${C.off}`);
  const r = spawnSync(bin, ["--headless", "--path", PROJET, "--export-release", "Web", cible], {
    encoding: "utf8",
  });

  const manquants = ATTENDUS.filter((f) => !fs.existsSync(path.join(chantier, f)));
  if (r.status !== 0 || manquants.length) {
    fs.rmSync(chantier, { recursive: true, force: true });
    console.error(`${C.red}L'export a échoué — ${path.relative(ROOT, SORTIE)}/ est laissé intact.${C.off}`);
    if (manquants.length) console.error(`  fichiers non produits : ${manquants.join(", ")}`);
    /* La cause la plus fréquente, et la seule que l'on puisse nommer : les
     * modèles d'export ne se téléchargent pas avec le moteur. */
    if ((r.stderr ?? "").includes("template") || (r.stdout ?? "").includes("template")) {
      console.error("\n  Modèles d'export absents. Dans Godot :");
      console.error("  Éditeur → Gérer les modèles d'exportation → Télécharger");
    }
    process.exit(1);
  }

  fs.rmSync(SORTIE, { recursive: true, force: true });
  fs.renameSync(chantier, SORTIE);

  let octets = 0;
  for (const f of fs.readdirSync(SORTIE)) octets += fs.statSync(path.join(SORTIE, f)).size;
  const mo = (n: number) => (n / 1e6).toFixed(1) + " Mo";

  console.log(`${C.green}✓${C.off} jeu exporté dans ${path.relative(ROOT, SORTIE)}/`);
  for (const f of ATTENDUS) {
    console.log(`  ${f.padEnd(12)} ${mo(fs.statSync(path.join(SORTIE, f)).size)}`);
  }
  console.log(`  ${"total".padEnd(12)} ${mo(octets)}`);
  console.log(`${C.dim}Le site le sert sous /jeu/ — onglet « Jeu ».${C.off}`);
}

main();
