/**
 * Vérifie l'installation de bout en bout : fichiers d'index, clé API, et les
 * trois comportements de l'API dont dépend l'application (streaming, citations
 * sur documents, sorties structurées).
 *
 * Les citations et les sorties structurées sont testées pour de vrai parce que
 * l'application les utilise avec un repli : ce script dit lequel des deux
 * chemins sera emprunté, au lieu de le laisser deviner.
 */
import fs from "node:fs";
import path from "node:path";
import Anthropic from "@anthropic-ai/sdk";
import { loadEnv } from "../lib/env.ts";
import { BOOKS, SAGAS, bookId, sagaOf } from "../lib/books.ts";
import { CODEX_MODEL } from "../lib/claude.ts";
import { credentials, oauthProfiles } from "../lib/credentials.ts";

loadEnv();

const ROOT = path.resolve(import.meta.dirname, "..");
const MODEL = process.env.OMNIDIEV_MODEL ?? "claude-opus-5";

const C = {
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  bold: "\x1b[1m",
  off: "\x1b[0m",
};

let failures = 0;
const ok = (m: string) => console.log(`  ${C.green}✓${C.off} ${m}`);

const warn = (m: string) => console.log(`  ${C.yellow}!${C.off} ${m}`);
const bad = (m: string) => { failures++; console.log(`  ${C.red}✗${C.off} ${m}`); };
const head = (m: string) => console.log(`\n${C.bold}${m}${C.off}`);

const size = (p: string) => (fs.statSync(p).size / 1e6).toFixed(1) + " Mo";

/**
 * Distingue un refus de compte (crédits, clé, permissions) d'une fonctionnalité
 * que le modèle ne prend pas en charge.
 *
 * Sans cette distinction, un solde épuisé se présentait comme « citations
 * refusées, repli automatique » — un diagnostic faux qui envoyait chercher le
 * problème dans le code plutôt que dans la facturation.
 */
function accountIssue(err: unknown): string | null {
  const m = (err as Error).message ?? "";
  if (/credit balance/i.test(m)) return "solde de crédits épuisé — rechargez sur console.anthropic.com → Plans & Billing";
  if (/authentication|invalid x-api-key/i.test(m)) return "clé API invalide ou révoquée";
  if (/permission|not allowed/i.test(m)) return "la clé n'a pas accès à ce modèle";
  if (/rate limit/i.test(m)) return "limite de débit atteinte — réessayez dans un instant";
  return null;
}

async function main() {
  head("Sources");
  for (const saga of SAGAS) {
    const dir = path.join(ROOT, saga.dir);
    const books = BOOKS.filter((b) => b.saga === saga.id);
    if (!fs.existsSync(dir)) {
      bad(`dossier ${saga.dir}/ introuvable (${saga.name})`);
      continue;
    }
    const missing = books.filter((b) => !fs.existsSync(path.join(dir, b.source)));
    if (missing.length) {
      bad(`${saga.name} : ${missing.length} PDF manquants — ${missing.map(bookId).join(", ")}`);
    } else {
      const scans = books.filter((b) => b.quality === "scan").length;
      ok(`${saga.name} : ${books.length} PDF présents${scans ? ` (${scans} scannés)` : ""}`);
    }
  }

  head("Index");
  const idx = path.join(ROOT, "data", "index");
  for (const f of ["chunks.json", "bm25.json", "manifest.json"]) {
    const p = path.join(idx, f);
    if (fs.existsSync(p)) ok(`${f} (${size(p)})`);
    else bad(`${f} absent — lancez : npm run corpus`);
  }

  const emb = path.join(idx, "embeddings.bin");
  const embMeta = path.join(idx, "embeddings.json");
  const chunksPath = path.join(idx, "chunks.json");
  if (fs.existsSync(emb) && fs.existsSync(embMeta)) {
    const meta = JSON.parse(fs.readFileSync(embMeta, "utf8"));
    const chunks = fs.existsSync(chunksPath)
      ? JSON.parse(fs.readFileSync(chunksPath, "utf8")).length
      : 0;
    if (chunks && meta.count !== chunks) {
      bad(`embeddings.bin désynchronisé : ${meta.count} vecteurs pour ${chunks} fragments — relancez : npm run embed`);
    } else {
      ok(`embeddings.bin (${size(emb)}, ${meta.count} × ${meta.dim})`);
    }
  } else {
    warn("embeddings absents — recherche lexicale seule. Lancez : npm run embed");
  }

  const codex = path.join(idx, "codex.json");
  if (fs.existsSync(codex)) {
    const c = JSON.parse(fs.readFileSync(codex, "utf8"));
    ok(`codex.json (${c.entries.length} fiches, ${c.chapters.length} résumés de chapitre)`);
  } else {
    warn("codex absent — les questions de synthèse seront plus faibles. Lancez : npm run codex");
  }

  head("API Claude");
  const cred = credentials();
  if (!cred.source) {
    const profils = oauthProfiles();
    bad("aucun identifiant Anthropic");
    console.log("      soit une clé : copiez .env.example vers .env.local et renseignez ANTHROPIC_API_KEY");
    console.log("      soit un profil : brew install anthropics/tap/ant && ant auth login");
    if (profils.length) console.log(`      (profils trouvés mais non actifs : ${profils.join(", ")})`);
    return report();
  }
  ok(cred.label);
  if (cred.warning) warn(cred.warning);

  const client = new Anthropic();
  let blocked: string | null = null;

  // 1 — streaming sur le modèle de conversation
  try {
    const stream = client.messages.stream({
      model: MODEL,
      max_tokens: 64,
      messages: [{ role: "user", content: "Réponds exactement : bonjour" }],
    });
    let text = "";
    for await (const e of stream) {
      if (e.type === "content_block_delta" && e.delta.type === "text_delta") text += e.delta.text;
    }
    await stream.finalMessage();
    ok(`streaming ${MODEL} — « ${text.trim().slice(0, 24)} »`);
  } catch (err) {
    blocked = accountIssue(err);
    if (blocked) bad(`API inaccessible : ${blocked}`);
    else bad(`streaming ${MODEL} : ${(err as Error).message}`);
  }

  // 2 — citations sur bloc document : c'est ce qui rend les réponses vérifiables
  // Inutile d'insister si le compte lui-même est bloqué : le même 400 reviendrait
  // en se faisant passer pour un refus de fonctionnalité.
  if (blocked) warn("citations et sorties structurées non testées — API inaccessible");
  else try {
    const res = await client.messages.create({
      model: MODEL,
      max_tokens: 300,
      messages: [{
        role: "user",
        content: [
          {
            type: "document",
            source: {
              type: "text",
              media_type: "text/plain",
              data: "Le Chevalier Wellan portait une armure verte.\nSon cheval s'appelait Bruny.",
            },
            title: "[1] Test",
            citations: { enabled: true },
          },
          { type: "text", text: "De quelle couleur est l'armure ? Réponds en une phrase." },
        ],
      }],
    });
    const cited = res.content.some((b) => b.type === "text" && (b.citations?.length ?? 0) > 0);
    if (cited) ok("citations sur documents — actives (réponses vérifiables)");
    else warn("citations acceptées mais aucune renvoyée — les sources restent affichées dans l'interface");
  } catch (err) {
    warn(`citations refusées, l'application basculera sur le repli : ${(err as Error).message}`);
  }

  // 3 — sorties structurées sur le modèle du Codex
  if (!blocked) try {
    const res = await client.messages.create({
      model: CODEX_MODEL,
      max_tokens: 200,
      messages: [{ role: "user", content: "Donne le nom du héros : Wellan." }],
      output_config: {
        format: {
          type: "json_schema",
          schema: {
            type: "object",
            properties: { nom: { type: "string" } },
            required: ["nom"],
            additionalProperties: false,
          },
        },
      },
    });
    const t = res.content.filter((b) => b.type === "text").map((b) => b.text).join("");
    JSON.parse(t);
    ok(`sorties structurées ${CODEX_MODEL} — actives`);
  } catch (err) {
    warn(`sorties structurées indisponibles, le Codex utilisera le repli JSON : ${(err as Error).message}`);
  }

  head("Recherche");
  try {
    const { search } = await import("../lib/retrieve.ts");
    const t0 = Date.now();
    const hits = await search("Qui est Onyx ?", { limit: 3 });
    if (!hits.length) bad("aucun résultat — l'index est peut-être vide");
    else {
      ok(`${hits.length} extraits en ${Date.now() - t0} ms`);
      const sagas = new Set(hits.map((h) => h.chunk.saga));
      for (const h of hits) console.log(`      ${h.chunk.ref}`);
      if (sagas.size > 1) ok(`recherche transverse : ${sagas.size} épopées atteintes`);
    }
  } catch (err) {
    bad(`recherche : ${(err as Error).message}`);
  }

  report();
}

function report() {
  console.log(
    failures === 0
      ? `\n${C.green}Tout est prêt.${C.off}  Lancez : npm run dev\n`
      : `\n${C.red}${failures} problème(s) à corriger.${C.off}\n`,
  );
  // onnxruntime garde des threads vivants : un process.exit() immédiat le fait
  // avorter avec « mutex lock failed » après le rapport. On laisse la boucle
  // d'événements se vider, et on force la sortie seulement si elle s'attarde.
  process.exitCode = failures ? 1 : 0;
  setTimeout(() => process.exit(process.exitCode), 1500).unref();
}

main();
