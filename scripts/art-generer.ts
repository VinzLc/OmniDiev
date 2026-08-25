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
import { animate, awaitJobs, balance, characterZip, characters, money } from "../lib/pixellab.ts";

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

async function main() {
  if (process.argv.includes("--solde")) { await showBalance(); return; }

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
