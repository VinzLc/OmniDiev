/**
 * Construit le corpus interrogeable à partir de data/raw/.
 *
 *   texte brut → réparation OCR → parsing → fragments → index BM25
 *
 * Les deux épopées forment un seul index : « Les Héritiers d'Enkidiev » est la
 * suite directe des « Chevaliers d'Émeraude », et une question sur Onyx doit
 * pouvoir traverser les vingt-quatre tomes.
 *
 * Sorties dans data/index/ : chunks.json, bm25.json, manifest.json
 */
import fs from "node:fs";
import path from "node:path";
import { BOOKS, SAGAS, bookId, sagaOf } from "../lib/books.ts";
import { parseBook, collectVocab } from "../lib/parse.ts";
import { buildDictionary, repairText } from "../lib/ocr-repair.ts";
import { chunkBook, type Chunk } from "../lib/chunk.ts";
import { buildBm25 } from "../lib/bm25.ts";
import { dedupe } from "../lib/dedup.ts";

const ROOT = path.resolve(import.meta.dirname, "..");
const RAW = path.join(ROOT, "data", "raw");
const OUT = path.join(ROOT, "data", "index");

const rawPath = (b: (typeof BOOKS)[number]) => path.join(RAW, `${bookId(b)}.txt`);

function main() {
  const missing = BOOKS.filter((b) => !fs.existsSync(rawPath(b)));
  if (missing.length) {
    console.error(`Texte brut absent pour : ${missing.map(bookId).join(", ")}`);
    console.error("Lancez d'abord : npm run extract");
    process.exit(1);
  }

  const raws = new Map<number, string>();
  for (const b of BOOKS) raws.set(b.order, fs.readFileSync(rawPath(b), "utf8"));

  // Les tomes à couche texte propre — des deux épopées — servent de dictionnaire
  // aux tomes scannés. Y inclure l'épopée 2 est indispensable : sans elle, les
  // noms propres d'Enkidiev seraient inconnus, donc candidats à la correction.
  const clean = BOOKS.filter((b) => b.quality === "clean");
  const dict = buildDictionary(collectVocab(clean.map((b) => raws.get(b.order)!)));
  console.log(
    `Dictionnaire de référence : ${dict.freq.size} formes issues de ${clean.length} tomes propres\n`,
  );

  const scanned = BOOKS.filter((b) => b.quality === "scan");
  for (const b of scanned) {
    const { text, stats } = repairText(raws.get(b.order)!, dict);
    raws.set(b.order, text);
    const pct = (n: number) => ((n / stats.tokens) * 100).toFixed(1);
    console.log(
      `${bookId(b)} réparation OCR : ${String(stats.fixed).padStart(5)} corrections · ` +
      `inconnues ${pct(stats.unknownBefore).padStart(4)} % → ${pct(stats.unknownAfter).padStart(4)} % · ` +
      `${stats.protectedNames} noms protégés`,
    );
  }
  if (scanned.length) console.log();

  // Vocabulaire d'arbitrage des césures, recalculé après réparation.
  const vocab = collectVocab([...raws.values()]);

  const chunks: Chunk[] = [];
  const perBook: {
    id: string; saga: number; tome: number; order: number; title: string;
    chapters: number; chunks: number; chars: number; pages: number; quality: string;
  }[] = [];
  const warnings: string[] = [];

  for (const b of BOOKS) {
    const parsed = parseBook(b, raws.get(b.order)!, vocab);
    warnings.push(...parsed.warnings);
    const cs = chunkBook(parsed);
    chunks.push(...cs);

    const chars = parsed.paragraphs.reduce((s, p) => s + p.text.length, 0);
    const pages = parsed.paragraphs.at(-1)?.page ?? 0;
    perBook.push({
      id: bookId(b), saga: b.saga, tome: b.tome, order: b.order, title: b.title,
      chapters: parsed.chapters.length, chunks: cs.length, chars, pages, quality: b.quality,
    });

    console.log(
      `${bookId(b)} ${b.title.padEnd(30).slice(0, 30)} ` +
      `${String(parsed.chapters.length).padStart(3)} chap  ` +
      `${String(cs.length).padStart(4)} frag  ` +
      `${(chars / 1000).toFixed(0).padStart(4)} k car  ${String(pages).padStart(3)} p.`,
    );
  }

  const before = chunks.length;
  const { kept, dropped } = dedupe(chunks.map((c) => c.text));
  const unique = kept.map((i) => chunks[i]);
  if (dropped.length) {
    const byBook = new Map<string, number>();
    for (const d of dropped) {
      const id = `E${chunks[d.index].saga}T${String(chunks[d.index].tome).padStart(2, "0")}`;
      byBook.set(id, (byBook.get(id) ?? 0) + 1);
    }
    const top = [...byBook].sort((a, b) => b[1] - a[1]).slice(0, 6);
    console.log(
      `\n${dropped.length} fragments redondants écartés sur ${before} ` +
      `(prologues récapitulatifs) — ${top.map(([id, n]) => `${id}:${n}`).join(" ")}`,
    );
  }
  chunks.length = 0;
  chunks.push(...unique);

  console.log(`\nIndexation BM25 de ${chunks.length} fragments…`);
  const bm25 = buildBm25(chunks.map((c) => `${c.ref}\n${c.text}`));

  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, "chunks.json"), JSON.stringify(chunks));
  fs.writeFileSync(path.join(OUT, "bm25.json"), JSON.stringify(bm25));
  fs.writeFileSync(
    path.join(OUT, "manifest.json"),
    JSON.stringify(
      {
        builtAt: new Date().toISOString(),
        chunks: chunks.length,
        terms: Object.keys(bm25.postings).length,
        sagas: SAGAS.map((s) => ({
          id: s.id,
          name: s.name,
          books: perBook.filter((b) => b.saga === s.id).length,
          pages: perBook.filter((b) => b.saga === s.id).reduce((n, b) => n + b.pages, 0),
        })),
        books: perBook,
      },
      null,
      2,
    ),
  );

  const size = (f: string) => (fs.statSync(path.join(OUT, f)).size / 1e6).toFixed(1) + " Mo";
  const pages = perBook.reduce((n, b) => n + b.pages, 0);
  console.log(
    `\n${chunks.length} fragments · ${Object.keys(bm25.postings).length} termes · ` +
    `${pages} pages · ${BOOKS.length} tomes`,
  );
  for (const s of SAGAS) {
    const bs = perBook.filter((b) => b.saga === s.id);
    console.log(`  ${sagaOf(s.id).name} : ${bs.length} tomes, ${bs.reduce((n, b) => n + b.chunks, 0)} fragments`);
  }
  console.log(`chunks.json ${size("chunks.json")} · bm25.json ${size("bm25.json")}`);

  if (warnings.length) console.log("\nAvertissements :\n  " + warnings.join("\n  "));

  // Les vecteurs deviennent obsolètes dès que le nombre de fragments change.
  const emb = path.join(OUT, "embeddings.json");
  if (fs.existsSync(emb)) {
    const meta = JSON.parse(fs.readFileSync(emb, "utf8"));
    if (meta.count !== chunks.length) {
      console.log(`\n⚠ embeddings désynchronisés (${meta.count} vecteurs) — relancez : npm run embed`);
    }
  }
}

main();
