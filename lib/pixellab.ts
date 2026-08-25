/**
 * Client de l'API PixelLab.
 *
 * Le service est payant et facture à la génération. Tout ce qui suit est donc
 * écrit autour d'une seule discipline : ne jamais dépenser sans savoir combien,
 * et ne jamais dépenser plus que ce qui a été demandé.
 *
 * Chaque travail rend son coût. Le client les additionne et le fait remonter,
 * pour qu'une commande dise à la fin ce qu'elle a consommé plutôt que de le
 * laisser découvrir sur une facture.
 */
import { loadEnv } from "./env.ts";

const BASE = "https://api.pixellab.ai/v2";

export type Balance = {
  credits: { type: string; usd: number };
  subscription: { type: string; status: string; plan: string | null; generations: number; total: number };
};

export type Usage = { type: string; usd: number } | null;

export type Job = {
  id: string;
  status: "processing" | "completed" | "failed" | string;
  usage: Usage;
  created_at: string;
  last_response: Record<string, unknown> | null;
};

function key(): string {
  loadEnv();
  const k = process.env.PIXELLAB_API_KEY;
  if (!k) {
    throw new Error(
      "PIXELLAB_API_KEY absente. L'ajouter à .env.local :\n" +
      "  PIXELLAB_API_KEY=votre_clé      (https://www.pixellab.ai/pixellab-api)",
    );
  }
  return k;
}

async function call(path: string, init: RequestInit = {}): Promise<Response> {
  const r = await fetch(`${BASE}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${key()}`, ...(init.headers ?? {}) },
  });
  if (r.status === 429) throw new Error("PixelLab : trop de travaux simultanés (429). Enchaîner au lieu de paralléliser.");
  if (!r.ok) {
    const body = await r.text();
    throw new Error(`PixelLab ${init.method ?? "GET"} ${path} → ${r.status}\n${body.slice(0, 600)}`);
  }
  return r;
}

export async function balance(): Promise<Balance> {
  return (await call("/balance")).json();
}

export async function post<T>(path: string, body: unknown): Promise<T> {
  const r = await call(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return r.json();
}

export async function job(id: string): Promise<Job> {
  return (await call(`/background-jobs/${id}`)).json();
}

/**
 * Attend la fin des travaux, en additionnant ce qu'ils coûtent.
 *
 * L'API rejette les appels trop rapprochés (429) : on interroge posément, et un
 * travail par direction plutôt que tous d'un coup.
 */
export async function awaitJobs(
  ids: string[],
  onTick?: (done: number, total: number, spent: number) => void,
): Promise<{ jobs: Job[]; spent: number }> {
  const jobs = new Map<string, Job>();
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

  for (let round = 0; round < 240; round++) {
    for (const id of ids) {
      if (jobs.get(id)?.status === "completed" || jobs.get(id)?.status === "failed") continue;
      jobs.set(id, await job(id));
      await wait(250);
    }
    const done = [...jobs.values()].filter((j) => j.status === "completed" || j.status === "failed").length;
    const spent = [...jobs.values()].reduce((n, j) => n + (j.usage?.usd ?? 0), 0);
    onTick?.(done, ids.length, spent);
    if (done === ids.length) break;
    await wait(5000);
  }

  const list = ids.map((id) => jobs.get(id)!).filter(Boolean);
  return { jobs: list, spent: list.reduce((n, j) => n + (j.usage?.usd ?? 0), 0) };
}

export type CharacterSummary = { id: string; name: string; state_name?: string; prompt?: string };

export async function characters(): Promise<CharacterSummary[]> {
  const j = await (await call("/characters")).json();
  return Array.isArray(j) ? j : (j.characters ?? j.data ?? j.items ?? []);
}

/** L'archive d'un personnage : mêmes dossiers que l'export de l'interface. */
export async function characterZip(id: string, states?: string): Promise<Buffer> {
  const q = states ? `?states=${encodeURIComponent(states)}` : "";
  const r = await call(`/characters/${id}/zip${q}`);
  return Buffer.from(await r.arrayBuffer());
}

/**
 * Ajoute une animation à un personnage existant.
 *
 * Reprendre le `character_id` plutôt que d'en décrire un nouveau est ce qui
 * garantit que le personnage animé soit le même que celui déjà validé — la
 * cohérence cesse d'être une affaire de chance.
 *
 * Les modes ne coûtent pas la même chose, et l'écart est considérable :
 * « template » consomme une génération par direction, « v3 » se règle au nombre
 * d'images, « pro » en consomme vingt à quarante par direction. On ne s'y
 * aventure pas sans l'avoir voulu.
 */
export async function animate(opts: {
  character_id: string;
  action_description: string;
  animation_name?: string;
  directions: string[];
  frame_count?: number;
  mode?: "template" | "v3" | "pro";
}): Promise<{ background_job_ids: string[]; directions: string[]; status: string }> {
  return post("/characters/animations", {
    mode: "v3",
    frame_count: 4,
    keep_first_frame: true,
    ...opts,
  });
}

export const money = (usd: number) => `${usd.toFixed(3)} USD`;
