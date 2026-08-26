/**
 * Commande une animation à PixelLab pour un personnage déjà créé.
 *
 * Le service facture à la génération, et les modes n'ont pas le même appétit :
 * « pro » consomme vingt à quarante générations par direction. Cette commande
 * n'anime donc qu'une direction si on ne lui en demande pas plus, annonce le
 * solde avant, le coût après, et refuse d'engager les quatre sans qu'on l'ait
 * écrit.
 *
 * Le résultat atterrit dans jeu/art/sources/<id>/ — exactement là où
 * `npm run art:normalise` va le chercher. Le circuit ne change pas ; il gagne
 * une entrée automatique.
 *
 * Usage :
 *   npm run art:generer -- --perso Wellan --action "walking"
 *   npm run art:generer -- --perso Wellan --action "walking" --directions south,north,east,west
 *   npm run art:generer -- --solde
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import sharp from "sharp";
import { animate, awaitJobs, balance, characterZip, characters, get, money, post } from "../lib/pixellab.ts";

const ROOT = path.resolve(import.meta.dirname, "..");
const SOURCES = path.join(ROOT, "jeu", "art", "sources");

const C = { red: "\x1b[31m", yellow: "\x1b[33m", green: "\x1b[32m", dim: "\x1b[2m", off: "\x1b[0m" };

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function showBalance(prefix = "Solde") {
  const b = await balance();
  const sub = b.subscription;
  const extra = sub?.generations != null ? `, ${sub.generations}/${sub.total} générations (${sub.status})` : "";
  console.log(`${C.dim}${prefix} : ${money(b.credits.usd)}${extra}${C.off}`);
  return b;
}

/**
 * La palette du monde en image, pour `color_image`.
 *
 * Le service accepte une image de référence et sait s'y tenir. Imposer les
 * couleurs à la génération vaut mieux que les rattraper après coup : ce qui
 * n'est jamais sorti de la palette n'a pas de modelé à perdre.
 */
async function paletteImage(): Promise<{ type: "base64"; base64: string; format: "png" }> {
  const src = fs.readFileSync(path.join(ROOT, "jeu", "art", "CONTEXTE.md"), "utf8");
  const hexes = [...new Set(src.match(/#[0-9A-Fa-f]{6}\b/g) ?? [])];
  const cols = Math.ceil(Math.sqrt(hexes.length));
  const rows = Math.ceil(hexes.length / cols);
  const cell = 16;
  const buf = Buffer.alloc(cols * cell * rows * cell * 4, 0);
  hexes.forEach((h, i) => {
    const [r, g, b] = [1, 3, 5].map((o) => parseInt(h.slice(o, o + 2), 16));
    const cx = (i % cols) * cell, cy = Math.floor(i / cols) * cell, W = cols * cell;
    for (let y = 0; y < cell; y++) for (let x = 0; x < cell; x++) {
      const o = ((cy + y) * W + cx + x) * 4;
      buf[o] = r; buf[o + 1] = g; buf[o + 2] = b; buf[o + 3] = 255;
    }
  });
  const png = await sharp(buf, { raw: { width: cols * cell, height: rows * cell, channels: 4 } }).png().toBuffer();
  console.log(`${C.dim}palette de référence : ${hexes.length} teintes, ${cols * cell}×${rows * cell} px${C.off}`);
  return { type: "base64", base64: png.toString("base64"), format: "png" };
}

/**
 * Crée un personnage à partir d'une commande versionnée.
 *
 * Le rendu va dans un dossier distinct : une régénération peut décevoir, et
 * écraser un personnage déjà validé pour découvrir ensuite que le nouveau est
 * moins bon coûterait bien plus qu'une génération.
 */
async function create(id: string) {
  const file = path.join(ROOT, "jeu", "art", "commandes", `${id}.pixellab.txt`);
  if (!fs.existsSync(file)) {
    console.error(`Commande absente : ${path.relative(ROOT, file)}`);
    process.exit(1);
  }
  const description = fs.readFileSync(file, "utf8").trim();
  const before = await showBalance("Solde avant");
  console.log(`\n${id} — création, ${description.length} caractères de description`);

  /*
   * `force_colors` et un rendu plat se paient cher sur un personnage.
   * Premier essai avec les deux : les cheveux ont bien viré au blond, mais le
   * géant est devenu frêle, l'armure a disparu, la croix dorée avec. Trois
   * variables changées d'un coup — on ne savait plus laquelle avait nui. Ils
   * sont donc explicites, et l'appel nu reproduit ce qui a marché.
   */
  const forcer = process.argv.includes("--forcer-couleurs");
  const body: Record<string, unknown> = {
    description,
    image_size: { width: 32, height: 32 },
    view: "low top-down",
    ...(forcer ? { color_image: await paletteImage(), force_colors: true, shading: "flat shading" } : {}),
  };

  const r = await post<Record<string, unknown>>("/create-character-with-4-directions", body);
  const ids = (r.background_job_ids as string[]) ?? [r.background_job_id as string].filter(Boolean);
  console.log(`personnage ${r.character_id}, ${ids.length} travail/travaux. Attente…`);

  const { spent } = await awaitJobs(ids, (d, t, usd) => process.stdout.write(`\r  ${d}/${t}   ${money(usd)}   `));
  console.log();

  const dir = path.join(SOURCES, `${id}-v2`);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, ".export.zip");
  fs.writeFileSync(tmp, await characterZip(String(r.character_id)));
  execFileSync("unzip", ["-o", "-q", tmp, "-d", dir]);
  fs.unlinkSync(tmp);

  const after = await balance();
  console.log(`\n${C.green}✓${C.off} ${path.relative(ROOT, dir)}/`);
  console.log(`${C.dim}coût ${money(spent)} — générations ${before.subscription?.generations} → ${after.subscription?.generations}${C.off}`);
  console.log(`\n${C.yellow}Regarder le rendu avant de remplacer l'existant.${C.off}`);
}

/**
 * Commande un jeu de tuiles.
 *
 * Le service produit un tileset de Wang : non pas des murs et des meubles, mais
 * le raccord complet entre deux sols — seize tuiles qui s'aboutent dans toutes
 * les combinaisons de coins. C'est exactement la partie qu'on ne réussit pas à
 * la main, et celle dont dépend qu'un décor ne montre pas ses coutures.
 */
async function tuiles(id: string) {
  const file = path.join(ROOT, "jeu", "art", "commandes", `${id}.tuiles.json`);
  if (!fs.existsSync(file)) {
    console.error(`Commande absente : ${path.relative(ROOT, file)}`);
    process.exit(1);
  }
  const spec = JSON.parse(fs.readFileSync(file, "utf8")) as Record<string, unknown>;
  for (const k of Object.keys(spec)) if (k.startsWith("_")) delete spec[k];

  const before = await showBalance("Solde avant");
  console.log(`\n${id} — jeu de tuiles 16×16`);

  const body = {
    ...spec,
    tile_size: { width: 16, height: 16 },
    view: "low top-down",
    outline: "single color black outline",
    shading: "basic shading",
    detail: "medium detail",
    color_image: await paletteImage(),
    ...spec, // la commande a le dernier mot sur le style
  };

  const r = await post<Record<string, unknown>>("/create-tileset", body);
  const tilesetId = String(r.tileset_id);
  console.log(`tileset ${tilesetId}. Attente…`);

  const { spent } = await awaitJobs([String(r.background_job_id)], (d, t, usd) =>
    process.stdout.write(`\r  ${d}/${t}   ${money(usd)}   `));
  console.log();

  const result = await get<Record<string, unknown>>(`/tilesets/${tilesetId}`);
  const dir = path.join(SOURCES, `${id}-tuiles`);
  fs.mkdirSync(dir, { recursive: true });

  /* On ne présume pas de la forme du résultat : on parcourt, on écrit ce qui
   * ressemble à une image, et on garde le reste tel quel pour l'examiner. */
  let n = 0;
  const walk = (o: unknown, chemin: string[]) => {
    if (Array.isArray(o)) return o.forEach((v, i) => walk(v, [...chemin, String(i)]));
    if (o && typeof o === "object") {
      for (const [k, v] of Object.entries(o as Record<string, unknown>)) {
        if (k === "base64" && typeof v === "string") {
          fs.writeFileSync(path.join(dir, `${chemin.join("-") || "tuile"}.png`), Buffer.from(v, "base64"));
          n++;
        } else walk(v, [...chemin, k]);
      }
    }
  };
  walk(result, []);
  fs.writeFileSync(path.join(dir, "reponse.json"),
    JSON.stringify(result, (k, v) => (k === "base64" ? "<image>" : v), 2));

  const after = await balance();
  console.log(`\n${C.green}✓${C.off} ${n} image(s) dans ${path.relative(ROOT, dir)}/`);
  console.log(`${C.dim}coût ${money(spent)} — générations ${before.subscription?.generations} → ${after.subscription?.generations}${C.off}`);
}

async function main() {
  if (process.argv.includes("--solde")) { await showBalance(); return; }
  const tuilesId = arg("tuiles");
  if (tuilesId) { await tuiles(tuilesId); return; }
  const creer = arg("creer");
  if (creer) { await create(creer); return; }

  const who = arg("perso");
  const action = arg("action") ?? "walking";
  const frames = Number(arg("frames") ?? 4);
  const dirs = (arg("directions") ?? "south").split(",").map((d) => d.trim()).filter(Boolean);

  if (!who) {
    console.error("Quel personnage ? Exemple : npm run art:generer -- --perso Wellan --action walking");
    process.exit(1);
  }

  const list = await characters();
  const match = list.filter((c) => c.name?.toLowerCase() === who.toLowerCase());
  if (!match.length) {
    console.error(`Aucun personnage nommé « ${who} » chez PixelLab.`);
    console.error(`Connus : ${[...new Set(list.map((c) => c.name))].join(", ") || "aucun"}`);
    process.exit(1);
  }

  /* Un personnage peut porter plusieurs états ; on anime à partir du repos,
   * qui est la pose de référence. */
  const base = match.find((c) => /idle|repos/i.test(c.state_name ?? "")) ?? match[0];

  const before = await showBalance("Solde avant");
  console.log(`\n${base.name} (${base.state_name ?? "—"})  ${C.dim}${base.id}${C.off}`);
  console.log(`animation « ${action} », ${frames} images, direction(s) : ${dirs.join(", ")}`);
  console.log(`${C.dim}mode v3 — une génération par image et par direction, environ${C.off}\n`);

  const started = await animate({
    character_id: base.id,
    action_description: action,
    animation_name: action,
    directions: dirs,
    frame_count: frames,
    mode: "v3",
  });

  const ids = started.background_job_ids ?? [];
  console.log(`${ids.length} travail/travaux lancé(s), un par direction. Attente…`);

  const { jobs, spent } = await awaitJobs(ids, (done, total, usd) => {
    process.stdout.write(`\r  ${done}/${total} terminé(s)   ${money(usd)} consommés   `);
  });
  console.log();

  const failed = jobs.filter((j) => j.status === "failed");
  for (const f of failed) console.log(`${C.red}✗${C.off} travail ${f.id} en échec`);

  const dir = path.join(SOURCES, base.name.toLowerCase());
  fs.mkdirSync(dir, { recursive: true });
  const zip = await characterZip(base.id);
  const tmp = path.join(dir, ".export.zip");
  fs.writeFileSync(tmp, zip);
  execFileSync("unzip", ["-o", "-q", tmp, "-d", dir]);
  fs.unlinkSync(tmp);

  const after = await balance();
  console.log(`\n${C.green}✓${C.off} archive dépliée dans ${path.relative(ROOT, dir)}/`);
  console.log(`${C.dim}coût annoncé par les travaux : ${money(spent)}${C.off}`);
  console.log(`${C.dim}solde : ${money(before.credits.usd)} → ${money(after.credits.usd)}`);
  if (before.subscription?.generations != null) {
    console.log(`générations d'essai : ${before.subscription.generations} → ${after.subscription.generations}${C.off}`);
  } else {
    console.log(C.off);
  }
  console.log(`\nEnsuite : npm run art:normalise -- ${base.name.toLowerCase()}`);
}

main().catch((e) => { console.error(`${C.red}${e.message}${C.off}`); process.exit(1); });
