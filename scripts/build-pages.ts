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

const ROOT = path.resolve(import.meta.dirname, "..");
const OUT = path.join(ROOT, "public", "codex");

function main() {
  const index = codexIndex();
  if (!index.ready) {
    console.error("Codex absent. Lancez d'abord : npm run codex");
    process.exit(1);
  }

  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });

  fs.writeFileSync(path.join(OUT, "index.json"), JSON.stringify(index));

  let bytes = 0;
  for (const id of codexIds()) {
    const detail = codexDetail(id);
    if (!detail) continue;
    const body = JSON.stringify(detail);
    bytes += body.length;
    fs.writeFileSync(path.join(OUT, `${id}.json`), body);
  }

  const size = (n: number) => (n / 1e6).toFixed(2) + " Mo";
  console.log(`${index.entries.length} fiches → ${path.relative(ROOT, OUT)}/`);
  console.log(`  index.json  ${size(fs.statSync(path.join(OUT, "index.json")).size)}`);
  console.log(`  fiches      ${size(bytes)}`);
  console.log(`  total       ${size(fs.statSync(path.join(OUT, "index.json")).size + bytes)}`);
}

main();
