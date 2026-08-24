/**
 * Calcule un vecteur par fragment, en local, sans clé API.
 *
 * Modèle : multilingual-e5-small (384 dimensions), qui attend les préfixes
 * « passage: » à l'indexation et « query: » à l'interrogation — c'est ce qui
 * lui permet de rapprocher une question de la réponse qui y correspond plutôt
 * que d'une question voisine.
 *
 * Sortie : data/index/embeddings.bin (Float32 brut) + embeddings.json
 */
import fs from "node:fs";
import path from "node:path";
import { pipeline } from "@huggingface/transformers";
import type { Chunk } from "../lib/chunk.ts";
import { EMBED_MODEL, EMBED_DIM, passageText } from "../lib/embed.ts";

const ROOT = path.resolve(import.meta.dirname, "..");
const OUT = path.join(ROOT, "data", "index");
const BATCH = 16;

const bar = (done: number, total: number) => {
  const w = 32;
  const f = Math.round((done / total) * w);
  return `[${"█".repeat(f)}${"·".repeat(w - f)}] ${((done / total) * 100).toFixed(1).padStart(5)} %`;
};

async function main() {
  const chunksPath = path.join(OUT, "chunks.json");
  if (!fs.existsSync(chunksPath)) {
    console.error("data/index/chunks.json absent — lancez d'abord : npm run corpus");
    process.exit(1);
  }
  const chunks: Chunk[] = JSON.parse(fs.readFileSync(chunksPath, "utf8"));

  console.log(`Chargement de ${EMBED_MODEL} (téléchargé une seule fois, mis en cache)…`);
  const t0 = Date.now();
  const extract = await pipeline("feature-extraction", EMBED_MODEL);
  console.log(`Modèle prêt en ${((Date.now() - t0) / 1000).toFixed(1)} s\n`);

  const out = new Float32Array(chunks.length * EMBED_DIM);
  const started = Date.now();

  for (let i = 0; i < chunks.length; i += BATCH) {
    const slice = chunks.slice(i, i + BATCH);
    const tensor = await extract(slice.map(passageText), { pooling: "mean", normalize: true });
    const data = tensor.data as Float32Array;
    out.set(data.subarray(0, slice.length * EMBED_DIM), i * EMBED_DIM);

    const done = Math.min(i + BATCH, chunks.length);
    const elapsed = (Date.now() - started) / 1000;
    const eta = elapsed / done * (chunks.length - done);
    process.stdout.write(`\r${bar(done, chunks.length)}  ${done}/${chunks.length}  reste ~${Math.ceil(eta)} s   `);
  }

  fs.writeFileSync(path.join(OUT, "embeddings.bin"), Buffer.from(out.buffer));
  fs.writeFileSync(
    path.join(OUT, "embeddings.json"),
    JSON.stringify({ model: EMBED_MODEL, dim: EMBED_DIM, count: chunks.length, builtAt: new Date().toISOString() }, null, 2),
  );

  console.log(
    `\n\n${chunks.length} vecteurs · ${EMBED_DIM} dimensions · ` +
    `${(out.byteLength / 1e6).toFixed(1)} Mo · ${((Date.now() - started) / 1000).toFixed(0)} s`,
  );
}

main();
