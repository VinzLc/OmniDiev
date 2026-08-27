/**
 * Construit le site statique du Codex, destiné à GitHub Pages.
 *
 * Seul le Codex est publié : ses fiches sont du texte généré. L'index de
 * recherche, lui, contient le texte intégral des romans et ne quitte jamais la
 * machine — c'est la raison d'être de ce périmètre restreint.
 *
 * Sortie : public/codex/index.json + public/codex/<id>.json
 */
import fs from "node:fs";
import path from "node:path";
import { codexIndex, codexDetail, codexIds } from "../lib/codex-view.ts";
import { genealogyIndex, genealogyTree, genealogyIds } from "../lib/genealogy-view.ts";

const ROOT = path.resolve(import.meta.dirname, "..");
const OUT = path.join(ROOT, "public", "codex");
const GEN = path.join(ROOT, "public", "genealogie");

function main() {
  const index = codexIndex();
  if (!index.ready) {
    console.error("Codex absent. Lancez d'abord : npm run codex");
    process.exit(1);
  }

  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });

  fs.writeFileSync(path.join(OUT, "index.json"), JSON.stringify(index));

  /*
   * Les visages suivent leurs fiches.
   *
   * Ils sont dessinés pour le jeu et vivent dans `jeu/art/portraits/`. Le site
   * en publie une copie plutôt que d'y pointer : `public/` est ce que le build
   * statique emporte, et un chemin vers un dossier de production ne survivrait
   * pas à la publication.
   */
  const source = path.join(ROOT, "jeu", "art", "portraits");
  let visages = 0;
  if (fs.existsSync(source)) {
    const dest = path.join(OUT, "portraits");
    fs.mkdirSync(dest, { recursive: true });
    // Ne publier que les visages qui correspondent à une fiche. Le tiret ne
    // distingue pas une humeur : « emeraude-ier » en porte un, et il avait
    // suffi à le laisser sans portrait.
    const fiches = new Set(codexIds());
    for (const f of fs.readdirSync(source)) {
      if (!f.endsWith(".png") || !fiches.has(f.slice(0, -4))) continue;
      fs.copyFileSync(path.join(source, f), path.join(dest, f));
      visages++;
    }
  }

  let bytes = 0;
  for (const id of codexIds()) {
    const detail = codexDetail(id);
    if (!detail) continue;
    const body = JSON.stringify(detail);
    bytes += body.length;
    fs.writeFileSync(path.join(OUT, `${id}.json`), body);
  }

  // ── Généalogie ──────────────────────────────────────────────────────────
  const gen = genealogyIndex();
  let genBytes = 0;
  if (gen.ready) {
    fs.rmSync(GEN, { recursive: true, force: true });
    fs.mkdirSync(GEN, { recursive: true });
    fs.writeFileSync(path.join(GEN, "index.json"), JSON.stringify(gen));
    for (const id of genealogyIds()) {
      const tree = genealogyTree(id);
      if (!tree) continue;
      const body = JSON.stringify(tree);
      genBytes += body.length;
      fs.writeFileSync(path.join(GEN, `${id}.json`), body);
    }
  }

  const size = (n: number) => (n / 1e6).toFixed(2) + " Mo";
  console.log(`${index.entries.length} fiches → ${path.relative(ROOT, OUT)}/`);
  console.log(`  index.json  ${size(fs.statSync(path.join(OUT, "index.json")).size)}`);
  console.log(`  portraits   ${visages}`);
  console.log(`  fiches      ${size(bytes)}`);
  console.log(`  total       ${size(fs.statSync(path.join(OUT, "index.json")).size + bytes)}`);
  if (gen.ready) {
    console.log(`${gen.trees.length} arbres → ${path.relative(ROOT, GEN)}/  ${size(genBytes)}`);
  } else {
    console.log("Généalogie absente — lancez : npm run genealogie");
  }
}

main();
