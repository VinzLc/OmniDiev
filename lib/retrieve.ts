/**
 * Recherche hybride sur le corpus : lexicale (BM25) + sémantique (e5).
 *
 * Les deux signaux sont complémentaires et se rattrapent l'un l'autre :
 * BM25 excelle sur les noms propres rares (« Amecareth », « Irianeth ») mais
 * s'effondre sur « Qui est Onyx ? », où le seul terme utile est justement le
 * plus fréquent du corpus ; le vecteur, lui, capte l'intention de la question
 * mais confond volontiers deux scènes de bataille.
 *
 * La fusion est un RRF (Reciprocal Rank Fusion) : elle ne combine que les rangs,
 * ce qui évite d'avoir à calibrer deux échelles de score incomparables.
 */
import fs from "node:fs";
import path from "node:path";
import { pipeline } from "@huggingface/transformers";
import type { Chunk } from "./chunk.ts";
import { searchBm25, type Bm25Index } from "./bm25.ts";
import { shingles, jaccard } from "./dedup.ts";
import { EMBED_MODEL, EMBED_DIM, queryText, cosine } from "./embed.ts";

const INDEX_DIR = path.join(process.cwd(), "data", "index");

export type Hit = {
  chunk: Chunk;
  score: number;
  /** Origine du fragment, pour expliquer le classement dans l'interface. */
  via: ("lexical" | "sémantique")[];
};

type Corpus = {
  chunks: Chunk[];
  bm25: Bm25Index;
  vectors: Float32Array | null;
};

let corpusPromise: Promise<Corpus> | null = null;
let embedderPromise: Promise<((q: string) => Promise<Float32Array>) | null> | null = null;

export function loadCorpus(): Promise<Corpus> {
  corpusPromise ??= (async () => {
    const read = (f: string) => path.join(INDEX_DIR, f);
    if (!fs.existsSync(read("chunks.json"))) {
      throw new Error("Index absent. Lancez : npm run ingest");
    }
    const chunks: Chunk[] = JSON.parse(fs.readFileSync(read("chunks.json"), "utf8"));
    const bm25: Bm25Index = JSON.parse(fs.readFileSync(read("bm25.json"), "utf8"));

    let vectors: Float32Array | null = null;
    if (fs.existsSync(read("embeddings.bin"))) {
      const buf = fs.readFileSync(read("embeddings.bin"));
      const expected = chunks.length * EMBED_DIM * 4;
      if (buf.byteLength === expected) {
        vectors = new Float32Array(buf.buffer, buf.byteOffset, chunks.length * EMBED_DIM);
      } else {
        console.warn(
          `embeddings.bin désynchronisé (${buf.byteLength} octets pour ${expected} attendus) — ` +
          `recherche lexicale seule. Relancez : npm run embed`,
        );
      }
    }
    return { chunks, bm25, vectors };
  })();
  return corpusPromise;
}

/** Le modèle est chargé paresseusement : une question lexicale n'en a pas besoin. */
function getEmbedder() {
  embedderPromise ??= (async () => {
    try {
      const extract = await pipeline("feature-extraction", EMBED_MODEL);
      return async (q: string) => {
        const t = await extract([queryText(q)], { pooling: "mean", normalize: true });
        return new Float32Array(t.data as Float32Array);
      };
    } catch (err) {
      console.warn("Modèle d'embeddings indisponible, recherche lexicale seule :", err);
      return null;
    }
  })();
  return embedderPromise;
}


/**
 * Second filet, après la déduplication faite à la construction de l'index :
 * deux fragments voisins d'un même passage peuvent rester distincts sans rien
 * apporter l'un à l'autre.
 */
const NEAR_DUPLICATE = 0.45;

const RRF_K = 60;

export type SearchOptions = {
  limit?: number;
  /**
   * Position absolue du dernier tome autorisé (1 à 24).
   * Sert au contrôle anti-divulgation : la recherche ignore tout ce qui suit.
   */
  maxOrder?: number | null;
  /** Nombre maximum de fragments retenus par chapitre, pour élargir la couverture. */
  perChapter?: number;
};

export async function search(query: string, opts: SearchOptions = {}): Promise<Hit[]> {
  const { limit = 14, maxOrder, perChapter = 2 } = opts;
  const { chunks, bm25, vectors } = await loadCorpus();

  const keep = (i: number) => !maxOrder || chunks[i].order <= maxOrder;

  const POOL = 90;
  const lexical = searchBm25(bm25, query, POOL * 2).filter((r) => keep(r.doc)).slice(0, POOL);

  let semantic: { doc: number; score: number }[] = [];
  const embed = vectors ? await getEmbedder() : null;
  if (embed && vectors) {
    const q = await embed(query);
    const scored: { doc: number; score: number }[] = [];
    for (let i = 0; i < chunks.length; i++) {
      if (!keep(i)) continue;
      scored.push({ doc: i, score: cosine(q, vectors, i * EMBED_DIM) });
    }
    scored.sort((a, b) => b.score - a.score);
    semantic = scored.slice(0, POOL);
  }

  const fused = new Map<number, { score: number; via: Set<Hit["via"][number]> }>();
  const add = (list: { doc: number }[], via: Hit["via"][number]) => {
    list.forEach((r, rank) => {
      const cur = fused.get(r.doc) ?? { score: 0, via: new Set<Hit["via"][number]>() };
      cur.score += 1 / (RRF_K + rank + 1);
      cur.via.add(via);
      fused.set(r.doc, cur);
    });
  };
  add(lexical, "lexical");
  add(semantic, "sémantique");

  const ranked = [...fused]
    .map(([doc, v]) => ({ doc, score: v.score, via: [...v.via] }))
    .sort((a, b) => b.score - a.score);

  // Deux plafonds, pour que les extraits retenus disent des choses différentes :
  // au plus `perChapter` fragments d'un même chapitre, et aucun quasi-doublon.
  const seen = new Map<string, number>();
  const kept: Set<string>[] = [];
  const hits: Hit[] = [];

  for (const r of ranked) {
    const c = chunks[r.doc];
    const key = `${c.order}:${c.chapter}`;
    const n = seen.get(key) ?? 0;
    if (n >= perChapter) continue;

    const sig = shingles(c.text);
    if (kept.some((k) => jaccard(sig, k) > NEAR_DUPLICATE)) continue;

    seen.set(key, n + 1);
    kept.push(sig);
    hits.push({ chunk: c, score: r.score, via: r.via });
    if (hits.length >= limit) break;
  }
  return hits;
}
