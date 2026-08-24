import { tokenize } from "./text.ts";

const K1 = 1.2;
const B = 0.75;

export type Bm25Index = {
  n: number;
  avgdl: number;
  docLen: number[];
  /** terme → paires [index du document, fréquence] aplaties */
  postings: Record<string, number[]>;
};

export function buildBm25(docs: string[]): Bm25Index {
  const postings: Record<string, number[]> = {};
  const docLen: number[] = [];
  let total = 0;

  docs.forEach((doc, i) => {
    const toks = tokenize(doc);
    docLen.push(toks.length);
    total += toks.length;

    const tf = new Map<string, number>();
    for (const t of toks) tf.set(t, (tf.get(t) ?? 0) + 1);
    for (const [term, f] of tf) {
      (postings[term] ??= []).push(i, f);
    }
  });

  return { n: docs.length, avgdl: total / Math.max(1, docs.length), docLen, postings };
}

/** Renvoie les `limit` meilleurs documents, score BM25 décroissant. */
export function searchBm25(index: Bm25Index, query: string, limit = 60): { doc: number; score: number }[] {
  const terms = tokenize(query);
  if (!terms.length) return [];

  const scores = new Map<number, number>();
  const seen = new Set<string>();

  for (const term of terms) {
    if (seen.has(term)) continue; // un terme répété ne compte qu'une fois
    seen.add(term);
    const post = index.postings[term];
    if (!post) continue;

    const df = post.length / 2;
    const idf = Math.log(1 + (index.n - df + 0.5) / (df + 0.5));

    for (let i = 0; i < post.length; i += 2) {
      const doc = post[i];
      const f = post[i + 1];
      const norm = f * (K1 + 1) / (f + K1 * (1 - B + B * index.docLen[doc] / index.avgdl));
      scores.set(doc, (scores.get(doc) ?? 0) + idf * norm);
    }
  }

  return [...scores]
    .map(([doc, score]) => ({ doc, score }))
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
}
