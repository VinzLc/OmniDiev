import fs from "node:fs";
import path from "node:path";
import { loadCodex } from "../lib/codex.ts";
import { fold } from "../lib/text.ts";

const l = loadCodex()!;
const KIN = /\b(p[èe]re|m[èe]re|fils|fille|fr[èe]re|s(?:œ|oe)ur|[ée]pou[xs]e?|enfant|parent)\b/i;
const ARMES = /\b(?:fr[èe]res?|s(?:œ|oe)urs?)\s+d['’\s]\s*armes?\b/i;

// Notes de mention par entité — la source réelle de la passe 2.
const notes = new Map<string, string[]>();
const dir = path.join("data", "codex-cache", "chapters");
for (const f of fs.readdirSync(dir)) {
  const d = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
  for (const e of d.entites ?? []) {
    const k = fold(e.nom ?? "");
    if (!k) continue;
    const list = notes.get(k);
    if (list) list.push(e.role); else notes.set(k, [e.role]);
  }
}

let total = 0, weak = 0;
const rows: string[] = [];

for (const e of l.codex.entries) {
  for (const r of e.relations) {
    if (!KIN.test(r.nature) || ARMES.test(r.nature)) continue;
    total++;
    const mine = notes.get(fold(e.name)) ?? [];
    const theirs = notes.get(fold(r.name)) ?? [];
    // Combien de mes propres mentions énoncent une parenté citant l'autre ?
    const inMine = mine.filter((n) => KIN.test(n) && fold(n).includes(fold(r.name))).length;
    const inTheirs = theirs.filter((n) => KIN.test(n) && fold(n).includes(fold(e.name))).length;
    const support = inMine + inTheirs;
    if (support <= 1 && mine.length >= 6) {
      weak++;
      if (rows.length < 12) {
        rows.push(`  ${e.name} → ${r.name} : ${r.nature.slice(0, 44)}` +
          `  [appuis ${support} / ${mine.length} mentions]`);
      }
    }
  }
}
console.log(`liens de parenté affirmés : ${total}`);
console.log(`appuyés par 0 ou 1 mention sur une entité bien documentée : ${weak} (${((weak / total) * 100).toFixed(0)} %)`);
console.log("\néchantillon :");
console.log(rows.join("\n"));
