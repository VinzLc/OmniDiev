/**
 * Liens de parenté à ne pas affirmer.
 *
 * Deux sources, de fiabilité différente :
 *   - le contrôle automatique (`npm run verifier`), dont on ne retient que les
 *     liens qu'AUCUNE mention n'appuie — écarter davantage risquerait de
 *     supprimer un fait vrai, ce qui est pire que l'erreur cherchée ;
 *   - data/corrections.json, où se consignent les corrections vérifiées à la
 *     main, pour les cas qui demandent un jugement que la machine rate.
 */
import fs from "node:fs";
import path from "node:path";
import { fold } from "./text.ts";

export type Rejection = { from: string; to: string; motif: string };

/** Un lieu que les passes n'ont pas relevé et qu'on rétablit à la main. */
export type LieuAjoute = { id: string; nom: string; role: string; motif: string };

const KIN =
  /\b(p[èe]re|m[èe]re|fils|fille|fr[èe]re|s(?:œ|oe)ur|[ée]pou[xs]e?|enfant|parent)\b/i;
const ARMES = /\b(?:fr[èe]res?|s(?:œ|oe)urs?)\s+d['’\s]\s*armes?\b/i;

/** Mentions relevées par entité, telles que les passes les ont produites. */
function notesByEntity(root: string) {
  const dir = path.join(root, "data", "codex-cache", "chapters");
  const map = new Map<string, string[]>();
  if (!fs.existsSync(dir)) return map;
  for (const f of fs.readdirSync(dir)) {
    const d = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
    for (const e of d.entites ?? []) {
      const k = fold(e.nom ?? "");
      if (!k || !e.role) continue;
      const list = map.get(k);
      if (list) list.push(e.role); else map.set(k, [e.role]);
    }
  }
  return map;
}

export function loadRejections(root = process.cwd()): Rejection[] {
  const out: Rejection[] = [];
  const seen = new Set<string>();
  const add = (from: string, to: string, motif: string) => {
    const k = `${fold(from)}|${fold(to)}`;
    if (seen.has(k)) return;
    seen.add(k);
    out.push({ from, to, motif });
  };

  // 1 — corrections humaines
  const manual = path.join(root, "data", "corrections.json");
  if (fs.existsSync(manual)) {
    const d = JSON.parse(fs.readFileSync(manual, "utf8"));
    for (const r of d.parenteRejetee ?? []) add(r.de, r.vers, r.motif);
  }

  // 2 — contrôle automatique, restreint aux liens sans le moindre appui
  const auto = path.join(root, "data", "index", "kin-rejected.json");
  if (!fs.existsSync(auto)) return out;

  const notes = notesByEntity(root);
  const asserts = (a: string, b: string) => {
    const list = notes.get(fold(a)) ?? [];
    return list.filter((n) => KIN.test(n) && !ARMES.test(n) && fold(n).includes(fold(b))).length;
  };

  for (const r of JSON.parse(fs.readFileSync(auto, "utf8")).rejected ?? []) {
    // Une seule note suffit à rendre le lien plausible : on laisse alors le
    // jugement à la lecture plutôt que de trancher au risque de se tromper.
    if (asserts(r.from, r.to) + asserts(r.to, r.from) > 0) continue;
    add(r.from, r.to, r.raison);
  }
  return out;
}

/**
 * Les lieux que l'Oracle a manqués.
 *
 * Le relevé des lieux est une passe de lecture comme les autres, et une passe
 * de lecture oublie. Le Royaume de Rubis en est la preuve : sept royaumes sont
 * nommés dans le premier tome, Wellan y est né, et il ne figure pas dans les
 * cinquante-sept lieux relevés. L'omission ne se voit que le jour où l'on veut
 * y placer une salle.
 *
 * On ne corrige pas `codex.json`, qui est produit : on déclare ici, et ce qui
 * consomme le Codex applique la correction. C'est la même règle que pour les
 * liens de parenté rejetés — le fichier dit ce qu'une machine a manqué, avec
 * le motif, et rien ne se perd au prochain `npm run codex`.
 */
export function loadLieuxAjoutes(root = process.cwd()): LieuAjoute[] {
  const manual = path.join(root, "data", "corrections.json");
  if (!fs.existsSync(manual)) return [];
  const d = JSON.parse(fs.readFileSync(manual, "utf8"));
  return (d.lieuxAjoutes ?? []) as LieuAjoute[];
}

/** Liens rejetés concernant une entité, dans un sens ou dans l'autre. */
export function rejectionsFor(name: string, all: Rejection[]): Rejection[] {
  const k = fold(name);
  return all.filter((r) => fold(r.from) === k || fold(r.to) === k);
}
