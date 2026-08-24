/**
 * Réparation OCR pour le tome 8, seul volume issu d'un scan (Internet Archive).
 *
 * Le principe : les onze autres tomes ont une couche texte propre et partagent
 * le vocabulaire, les noms propres et la typographie du tome 8. Ils servent donc
 * de dictionnaire de référence, ce qui évite d'écrire à la main une table de
 * corrections. Trois passes, de la plus sûre à la plus spéculative :
 *
 *   1. clé désaccentuée   — « chateau » → « château », « Emeraude » → « Émeraude »
 *   2. apostrophe élidée  — « Cest » → « C’est », « quil » → « qu’il »
 *   3. distance d'édition 1 — repêchage générique (index par variantes de
 *      suppression, façon SymSpell)
 *
 * Une correction n'est appliquée que si le mot d'origine est absent du corpus
 * propre et que la cible est attestée au moins `MIN_FREQ` fois. Le nombre de
 * corrections est rapporté par `repairStats` pour rester vérifiable.
 */

const MIN_FREQ = 4;

const deaccent = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");

/** Consonnes qui s'élident en français : l', d', j', n', m', t', s', c', qu'. */
const ELIDABLE = ["l", "d", "j", "n", "m", "t", "s", "c", "qu"];

export type Dictionary = {
  freq: Map<string, number>;
  /** clé désaccentuée minuscule → forme accentuée la plus fréquente */
  byDeaccent: Map<string, string>;
  /** variante par suppression d'un caractère → formes candidates */
  byDeletion: Map<string, string[]>;
};

function deletions(w: string): string[] {
  const out: string[] = [];
  for (let i = 0; i < w.length; i++) out.push(w.slice(0, i) + w.slice(i + 1));
  return out;
}

export function buildDictionary(freq: Map<string, number>): Dictionary {
  const byDeaccent = new Map<string, string>();
  const byDeletion = new Map<string, string[]>();

  for (const [w, n] of freq) {
    if (n < MIN_FREQ) continue;

    const key = deaccent(w);
    if (key !== w) {
      const cur = byDeaccent.get(key);
      if (!cur || (freq.get(cur) ?? 0) < n) byDeaccent.set(key, w);
    }

    if (w.length >= 4 && w.length <= 18) {
      for (const d of deletions(w)) {
        const bucket = byDeletion.get(d);
        if (bucket) { if (bucket.length < 8) bucket.push(w); }
        else byDeletion.set(d, [w]);
      }
    }
  }
  return { freq, byDeaccent, byDeletion };
}

/** Restitue la casse de `src` sur `dst` (Majuscule initiale ou TOUT EN CAPITALES). */
function matchCase(src: string, dst: string): string {
  if (src === src.toUpperCase() && src.length > 1) return dst.toUpperCase();
  if (src[0] === src[0]?.toUpperCase()) return dst[0].toUpperCase() + dst.slice(1);
  return dst;
}

export type RepairStats = {
  tokens: number;
  unknownBefore: number;
  unknownAfter: number;
  fixed: number;
  /** Noms propres du livre soustraits à la règle spéculative. */
  protectedNames: number;
  byRule: Record<string, number>;
};

function correct(
  token: string,
  dict: Dictionary,
  stats: RepairStats,
  selfAttested: Set<string>,
): string {
  const lower = token.toLowerCase();
  if (dict.freq.has(lower)) return token; // déjà attesté

  stats.unknownBefore++;
  const bump = (rule: string) => {
    stats.fixed++;
    stats.byRule[rule] = (stats.byRule[rule] ?? 0) + 1;
  };

  // 1 — accents perdus par l'OCR
  const accented = dict.byDeaccent.get(deaccent(lower));
  if (accented) { bump("accents"); return matchCase(token, accented); }

  // 2 — apostrophe d'élision avalée
  for (const p of ELIDABLE) {
    if (lower.length > p.length + 1 && lower.startsWith(p)) {
      const cand = p + "’" + lower.slice(p.length);
      if (dict.freq.has(cand)) { bump("apostrophe"); return matchCase(token, cand); }
      const candAcc = dict.byDeaccent.get(deaccent(cand));
      if (candAcc) { bump("apostrophe"); return matchCase(token, candAcc); }
    }
  }

  // 3 — distance d'édition 1, cible unique et suffisamment fréquente.
  //
  // Cette règle est la seule spéculative, et la seule dangereuse pour les noms
  // propres : « Océani » est à une lettre d'« océan », « Napashni » n'existe
  // dans aucun tome propre. On l'interdit donc sur les formes que le livre
  // atteste lui-même en abondance — un nom revenu cinquante fois avec la même
  // graphie est le nom d'un personnage, pas une coquille.
  if (lower.length >= 4 && !selfAttested.has(lower)) {
    const seen = new Map<string, number>();
    const probe = (key: string) => {
      for (const c of dict.byDeletion.get(key) ?? []) seen.set(c, dict.freq.get(c) ?? 0);
    };
    probe(lower);                              // insertion dans le token
    for (const d of deletions(lower)) probe(d); // suppression ou substitution

    if (seen.size) {
      const ranked = [...seen].sort((a, b) => b[1] - a[1]);
      // Ambigu si le second candidat est presque aussi fréquent : on s'abstient.
      if (ranked.length === 1 || ranked[0][1] > ranked[1][1] * 3) {
        bump("distance1");
        return matchCase(token, ranked[0][0]);
      }
    }
  }

  stats.unknownAfter++;
  return token;
}

/**
 * Répare le texte en préservant strictement les espaces : l'indentation porte
 * la structure des paragraphes, `lib/parse.ts` en dépend.
 */
/** Formes capitalisées que le livre répète assez pour les tenir pour siennes. */
function selfAttestedNames(raw: string, min = 12): Set<string> {
  const counts = new Map<string, number>();
  for (const m of raw.matchAll(/(?<![.!?…]\s)\b([A-ZÀ-Ý][a-zà-ÿ’-]{2,})\b/g)) {
    const k = m[1].toLowerCase();
    counts.set(k, (counts.get(k) ?? 0) + 1);
  }
  return new Set([...counts].filter(([, n]) => n >= min).map(([k]) => k));
}

export function repairText(raw: string, dict: Dictionary): { text: string; stats: RepairStats } {
  const stats: RepairStats = { tokens: 0, unknownBefore: 0, unknownAfter: 0, fixed: 0, protectedNames: 0, byRule: {} };
  const selfAttested = selfAttestedNames(raw);
  stats.protectedNames = selfAttested.size;

  const text = raw
    // Confusions de glyphes systématiques du scan.
    .replace(/\bI{2}\b/g, "Il")
    .replace(/(?<=[a-zà-ÿ])\|(?=[a-zà-ÿ])/gi, "l")
    .replace(/\|['’]/g, "l’")
    .replace(/\bcœ?ceur\b/gi, "cœur")
    .replace(/(?<=[a-zà-ÿ])4(?=[a-zà-ÿ])/gi, "à")
    .replace(/ 4 /g, " à ")
    // Le « à » du scan est tantôt un 4, tantôt un A capital en plein mot.
    .replace(/(?<=[a-zà-ÿ,;] )A(?= [a-zà-ÿ])/g, "à")
    .replace(/(?<=[a-zà-ÿ] )(?:4|À)(?= [a-zà-ÿ])/g, "à")
    .replace(/'/g, "’")
    // Tirets cadratins parasites en fin de ligne (artéfact de reliure).
    .replace(/\s+—\s*$/gm, "")
    // Mots découpés par une ponctuation fantôme.
    .replace(/([a-zà-ÿ])\s*\.\s*(?=[a-zà-ÿ]{2,}\b)/g, "$1$2")
    .replace(/[^\S\n]+$/gm, "");

  const repaired = text.replace(/[A-Za-zÀ-ÿŒœ’'-]+/g, (tok) => {
    stats.tokens++;
    // Un token purement alphabétique de 2 caractères ou moins n'est pas
    // corrigeable de façon fiable.
    if (tok.replace(/[^A-Za-zÀ-ÿŒœ]/g, "").length < 3) return tok;
    return correct(tok, dict, stats, selfAttested);
  });

  return { text: repaired, stats };
}
