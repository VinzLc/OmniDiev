import type { Chunk } from "./chunk.ts";

export const EMBED_MODEL = "Xenova/multilingual-e5-small";
export const EMBED_DIM = 384;

/** e5 tronque au-delà de 512 tokens ; on borne en amont pour rester explicite. */
const MAX_CHARS = 1900;

/** Le préfixe « passage: » fait partie du contrat du modèle e5. */
export function passageText(c: Chunk): string {
  return `passage: ${c.ref}\n${c.text}`.slice(0, MAX_CHARS);
}

export function queryText(q: string): string {
  return `query: ${q}`.slice(0, MAX_CHARS);
}

export function cosine(a: Float32Array, b: Float32Array, offset = 0): number {
  let s = 0;
  for (let i = 0; i < EMBED_DIM; i++) s += a[i] * b[offset + i];
  return s; // vecteurs déjà normalisés
}
