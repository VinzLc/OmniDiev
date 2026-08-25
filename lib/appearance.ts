/**
 * Extrait du texte des romans ce qui décrit l'apparence d'une entité.
 *
 * Les fiches du Codex disent qui est un personnage ; elles disent rarement à
 * quoi il ressemble. Or c'est précisément ce qu'il faut pour commander une
 * image. Le texte, lui, le dit — « les cheveux blond foncé frôlant ses épaules,
 * les yeux d'un bleu perçant » — et c'est cette phrase-là qui doit arriver dans
 * le prompt, plutôt qu'une invention plausible.
 */
import fs from "node:fs";
import path from "node:path";
import { BOOKS, bookId } from "./books.ts";
import { fold } from "./text.ts";
import { loadCodex } from "./codex.ts";

/** Vocabulaire de l'apparence : ce qui se dessine, pas ce qui se raconte. */
const LOOKS = [
  "cheveux", "yeux", "regard", "barbe", "peau", "teint", "visage", "traits",
  "carrure", "stature", "colosse", "géant", "silhouette", "taille",
  "cuirasse", "tunique", "surcot", "cape", "armure", "manteau", "robe",
  "vêtu", "vêtue", "habillé", "habillée", "portait", "arborait",
  "blond", "brun", "roux", "noir", "argenté", "mauve", "pâle", "sombre",
];

const LOOK_RE = new RegExp(`\\b(${LOOKS.join("|")})`, "i");

/** Une phrase qui ne fait qu'agir n'apprend rien sur l'apparence. */
const ACTION_RE = /\b(dit|répondit|demanda|s'écria|songea|comprit|décida|ordonna|expliqua|murmura)\b/i;

let corpus: string[] | null = null;

function sentences(): string[] {
  if (corpus) return corpus;
  const dir = path.join(process.cwd(), "data", "raw");
  let all = "";
  for (const b of BOOKS) {
    const p = path.join(dir, `${bookId(b)}.txt`);
    if (fs.existsSync(p)) all += " " + fs.readFileSync(p, "utf8");
  }
  return (corpus = all.replace(/\s+/g, " ").split(/(?<=[.!?])\s+/));
}

export type Trait = { text: string; score: number };

/**
 * Noms de tous les personnages connus — pour repérer quand une phrase parle
 * d'un autre qu'elle ne le paraît.
 */
let cast: string[] | null = null;
function everyone(): string[] {
  if (cast) return cast;
  const l = loadCodex();
  cast = l
    ? l.codex.entries.filter((e) => e.kind === "personnage").map((e) => fold(e.name))
    : [];
  return cast;
}

/**
 * Phrases décrivant `name`, les plus probantes d'abord.
 *
 * Il ne suffit pas qu'une phrase contienne le nom et du vocabulaire visuel :
 * « une femme aux longs cheveux blonds se jeta dans les bras de Wellan » ne
 * décrit pas Wellan. Deux garde-fous s'ajoutent donc à la densité — la présence
 * d'un autre personnage nommé, qui est presque toujours le vrai sujet de la
 * description, et la distance entre le nom et le mot d'apparence le plus proche.
 */
export function appearanceOf(name: string, extra: string[] = [], limit = 5): Trait[] {
  const names = [name, ...extra].map(fold).filter((n) => n.length >= 3);
  const others = everyone().filter((n) => !names.includes(n) && n.length >= 4);
  const out: Trait[] = [];

  for (const s of sentences()) {
    if (s.length < 40 || s.length > 300) continue;
    const f = fold(s);
    const at = names.map((n) => f.indexOf(n)).filter((i) => i >= 0);
    if (!at.length) continue;
    if (!LOOK_RE.test(s)) continue;
    if (ACTION_RE.test(s)) continue;

    // Un autre personnage nommé : c'est lui qu'on décrit, neuf fois sur dix.
    const intruders = others.filter((n) => f.includes(n)).length;
    if (intruders) continue;

    /*
     * Le nom doit être le SUJET de la description, pas un simple témoin.
     *
     * « une femme aux longs cheveux blonds se jeta dans les bras de Wellan »
     * contient le nom et le vocabulaire, mais décrit quelqu'un d'autre — et ce
     * quelqu'un n'est pas nommé, donc le filtre précédent ne le voit pas.
     * Seules trois tournures attribuent vraiment les traits au nom.
     */
    const n = names.find((x) => f.includes(x))!;
    const attributive = [
      // « Wellan était un géant », « Wellan portait une cuirasse »
      new RegExp(`${n}[^.]{0,30}\\b(etait|avait|portait|arborait|mesurait|semblait)\\b`),
      // « Wellan, ses cheveux… », « … ses yeux, dit Wellan »
      new RegExp(`${n}[^.]{0,60}\\b(ses|son|sa)\\s+(${LOOKS.map(fold).join("|")})`),
      // apposition : « Les cheveux blond foncé…, Wellan était… »
      new RegExp(`\\b(${LOOKS.map(fold).join("|")})[^.]{0,80},\\s*${n}\\b`),
    ];
    if (!attributive.some((re) => re.test(f))) continue;

    // Nom en position oblique : c'est un complément, pas le sujet décrit.
    if (new RegExp(`\\b(de|a|vers|chez|pour|avec|sur|contre)\\s+${n}\\b`).test(f)) continue;

    let score = 0;
    let nearest = Infinity;
    for (const w of LOOKS) {
      const i = f.indexOf(fold(w));
      if (i < 0) continue;
      score++;
      for (const a of at) nearest = Math.min(nearest, Math.abs(i - a));
    }
    if (nearest > 90) continue; // le mot d'apparence porte sur autre chose

    out.push({ text: s.trim(), score: score * 100 - nearest - s.length / 10 });
  }

  return out.sort((a, b) => b.score - a.score).slice(0, limit);
}

/** Description d'un lieu : mêmes règles, vocabulaire de l'architecture. */
const PLACE_WORDS = [
  "muraille", "tour", "tours", "pont-levis", "cour", "donjon", "forteresse",
  "pierre", "colline", "escalier", "voûte", "portail", "remparts", "toit",
  "salle", "couloir", "fenêtre", "torche", "bannière", "trône",
];

const PLACE_RE = new RegExp(`\\b(${PLACE_WORDS.join("|")})`, "i");

export function placeOf(name: string, limit = 5): Trait[] {
  const full = fold(name);
  /*
   * Le nom générique compte autant que le nom propre.
   * Les romans décrivent rarement « le Château d'Émeraude » ; ils décrivent
   * « le château », qui se dressait sur une colline. Chercher les deux.
   */
  const head = full.split(" ")[0];
  const keys = [...new Set([full, head])].filter((k) => k.length >= 4);
  const out: Trait[] = [];

  for (const s of sentences()) {
    if (s.length < 50 || s.length > 300) continue;
    const f = fold(s);
    const key = keys.find((k) => f.includes(k));
    if (!key) continue;
    if (!PLACE_RE.test(s)) continue;
    if (ACTION_RE.test(s)) continue;

    /*
     * Le lieu doit être ce qu'on décrit, non ce à quoi l'on compare.
     * « une cour cent fois plus vaste que celle du Château d'Émeraude » parle
     * d'ailleurs ; « le château se dressait sur une colline » parle bien de lui.
     */
    if (/\b(plus|moins|aussi)\b[^.]{0,40}\bque\b/.test(f)) continue;
    if (new RegExp(`celle?s?\\s+(du|de|des)\\s+${key}`).test(f)) continue;

    // Le motif locatif — « la cour du Château » — a été écarté : il retient des
    // scènes qui se passent au château sans jamais le décrire.
    const subject = [
      new RegExp(`${key}[^.]{0,40}\\b(etait|se dressait|se trouvait|comptait|s'elevait|occupait|abritait|possedait|surplombait|dominait)\\b`),
      new RegExp(`${key}[^.]{0,50}\\b(ses|son|sa)\\s+(${PLACE_WORDS.map(fold).join("|")})`),
    ];
    if (!subject.some((re) => re.test(f))) continue;

    let score = 0;
    for (const w of PLACE_WORDS) if (new RegExp(`\\b${fold(w)}`).test(f)) score++;
    out.push({ text: s.trim(), score: score * 100 - s.length / 10 });
  }

  return out.sort((a, b) => b.score - a.score).slice(0, limit);
}
