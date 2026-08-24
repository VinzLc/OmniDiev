/**
 * Détection de quasi-doublons entre fragments.
 *
 * À partir du tome VII, chaque volume s'ouvre sur un prologue qui récapitule les
 * précédents : le même paragraphe se retrouve à l'identique dans six tomes. Ces
 * répétitions n'apportent rien et occupent la place — une question sur Kira
 * ramenait cinq fois le même résumé au lieu de la réponse. Autant les retirer de
 * l'index plutôt que de les filtrer à chaque requête.
 *
 * La comparaison porte sur des n-grammes de mots (MinHash + bandes) : c'est
 * insensible aux menues variations d'une édition à l'autre, et linéaire en
 * nombre de fragments là où la comparaison deux à deux serait quadratique.
 */
import { tokenize } from "./text.ts";

const GRAM = 4;
const SKETCH = 16;
const BAND = 3;

function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

export function shingles(text: string): Set<string> {
  const words = tokenize(text);
  const out = new Set<string>();
  for (let i = 0; i + GRAM <= words.length; i++) out.add(words.slice(i, i + GRAM).join(" "));
  return out;
}

/** Les `SKETCH` plus petites empreintes : deux textes proches en partagent. */
function sketch(grams: Set<string>): number[] {
  const hs = [...grams].map(hash).sort((a, b) => a - b);
  return hs.slice(0, SKETCH);
}

export function jaccard(a: Set<string>, b: Set<string>): number {
  if (!a.size || !b.size) return 0;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  return inter / Math.min(a.size, b.size);
}

export type DuplicateReport = { kept: number[]; dropped: { index: number; sameAs: number }[] };

/**
 * Conserve la première occurrence de chaque texte, écarte les suivantes.
 *
 * L'ordre d'entrée fait foi : les fragments étant fournis dans l'ordre de
 * publication, c'est le tome d'origine qui est conservé et le rappel qui saute.
 */
export function dedupe(texts: string[], threshold = 0.6, minWords = 60): DuplicateReport {
  const buckets = new Map<string, number[]>();
  const grams: (Set<string> | null)[] = new Array(texts.length).fill(null);
  const kept: number[] = [];
  const dropped: { index: number; sameAs: number }[] = [];

  for (let i = 0; i < texts.length; i++) {
    const g = shingles(texts[i]);
    // Un fragment court n'a pas assez de matière pour qu'on juge de sa
    // redondance sans risque.
    if (g.size < minWords) { kept.push(i); continue; }

    const sk = sketch(g);
    const keys: string[] = [];
    for (let b = 0; b + BAND <= sk.length; b += BAND) keys.push(sk.slice(b, b + BAND).join(","));

    let twin = -1;
    const seen = new Set<number>();
    for (const k of keys) {
      for (const j of buckets.get(k) ?? []) {
        if (seen.has(j)) continue;
        seen.add(j);
        const other = grams[j];
        if (other && jaccard(g, other) >= threshold) { twin = j; break; }
      }
      if (twin >= 0) break;
    }

    if (twin >= 0) {
      dropped.push({ index: i, sameAs: twin });
      continue;
    }

    grams[i] = g;
    kept.push(i);
    for (const k of keys) {
      const bucket = buckets.get(k);
      if (bucket) bucket.push(i);
      else buckets.set(k, [i]);
    }
  }

  return { kept, dropped };
}
