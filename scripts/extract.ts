/**
 * Extrait le texte des PDF vers data/raw/, un fichier par tome.
 *
 * `pdftotext -layout` conserve l'indentation, ce qui donne les trois signaux
 * dont dépend le parsing : l'alinéa ouvre un paragraphe, l'en-tête courant et
 * le folio sont seuls sur leur ligne, et la césure de fin de ligne est préservée.
 *
 * La liste des tomes vient de lib/books.ts, jamais d'un script à tenir à jour
 * en parallèle : ajouter une épopée ne demande qu'une entrée dans le catalogue.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { BOOKS, bookId, bookLabel, sagaOf } from "../lib/books.ts";

const ROOT = path.resolve(import.meta.dirname, "..");
const OUT = path.join(ROOT, "data", "raw");

const only = process.argv.includes("--saga")
  ? Number(process.argv[process.argv.indexOf("--saga") + 1])
  : null;

function main() {
  try {
    execFileSync("pdftotext", ["-v"], { stdio: "ignore" });
  } catch {
    console.error("pdftotext introuvable. Installez poppler :\n  brew install poppler");
    process.exit(1);
  }

  fs.mkdirSync(OUT, { recursive: true });

  const books = only ? BOOKS.filter((b) => b.saga === only) : BOOKS;
  const missing: string[] = [];
  let done = 0;

  for (const b of books) {
    const src = path.join(ROOT, sagaOf(b.saga).dir, b.source);
    if (!fs.existsSync(src)) {
      missing.push(`${bookId(b)} — ${b.source}`);
      continue;
    }
    const dst = path.join(OUT, `${bookId(b)}.txt`);
    execFileSync("pdftotext", ["-q", "-layout", "-eol", "unix", src, dst]);
    const chars = fs.statSync(dst).size;
    console.log(`${bookId(b)}  ${String(Math.round(chars / 1000)).padStart(4)} k car  ${bookLabel(b)}`);
    done++;
  }

  console.log(`\n${done} tomes extraits vers ${path.relative(ROOT, OUT)}/`);

  if (missing.length) {
    console.error(`\n${missing.length} PDF introuvables :`);
    for (const m of missing) console.error(`  ${m}`);
    process.exit(1);
  }
}

main();
