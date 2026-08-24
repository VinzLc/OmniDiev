import Anthropic from "@anthropic-ai/sdk";

export const CODEX_MODEL = process.env.OMNIDIEV_CODEX_MODEL ?? "claude-haiku-4-5";

/** Tarifs Claude Haiku 4.5, en dollars par million de tokens. */
export const PRICING = { input: 1.0, output: 5.0 };

export type Spend = { input: number; output: number; calls: number };

export const newSpend = (): Spend => ({ input: 0, output: 0, calls: 0 });

export const dollars = (s: Spend) =>
  (s.input / 1e6) * PRICING.input + (s.output / 1e6) * PRICING.output;

/**
 * Demande une réponse JSON conforme à `schema`.
 *
 * Les sorties structurées garantissent la forme du résultat ; si le modèle ou
 * l'API les refuse, on retombe sur une consigne en langage naturel et on extrait
 * le premier objet JSON de la réponse — le script doit pouvoir tourner pendant
 * une heure sans qu'un refus de schéma fasse tout échouer.
 */
export async function askJson<T>(
  client: Anthropic,
  opts: {
    system: string;
    prompt: string;
    schema: Record<string, unknown>;
    maxTokens?: number;
    spend?: Spend;
    model?: string;
  },
): Promise<T | null> {
  const { system, prompt, schema, maxTokens = 2000, spend, model = CODEX_MODEL } = opts;

  const call = (structured: boolean) =>
    client.messages.create({
      model,
      max_tokens: maxTokens,
      system: structured ? system : `${system}\n\nRéponds UNIQUEMENT par un objet JSON valide, sans texte autour.`,
      messages: [{ role: "user", content: prompt }],
      ...(structured ? { output_config: { format: { type: "json_schema" as const, schema } } } : {}),
    });

  let msg;
  try {
    msg = await call(true);
  } catch (err) {
    if (!(err instanceof Anthropic.BadRequestError)) throw err;
    msg = await call(false);
  }

  if (spend) {
    spend.input += msg.usage.input_tokens;
    spend.output += msg.usage.output_tokens;
    spend.calls++;
  }

  const text = msg.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  return parseJson<T>(text);
}

function parseJson<T>(text: string): T | null {
  try {
    return JSON.parse(text) as T;
  } catch {
    // Repli : isole le premier objet complet, en ignorant les accolades des
    // chaînes de caractères.
    const start = text.indexOf("{");
    if (start < 0) return null;
    let depth = 0, inStr = false, esc = false;
    for (let i = start; i < text.length; i++) {
      const c = text[i];
      if (esc) { esc = false; continue; }
      if (c === "\\") { esc = true; continue; }
      if (c === '"') { inStr = !inStr; continue; }
      if (inStr) continue;
      if (c === "{") depth++;
      else if (c === "}" && --depth === 0) {
        try { return JSON.parse(text.slice(start, i + 1)) as T; } catch { return null; }
      }
    }
    return null;
  }
}

/** Réessaie avec un délai croissant : les 429 et 5xx sont attendus sur un long lot. */
export async function withRetry<T>(fn: () => Promise<T>, label: string, tries = 4): Promise<T | null> {
  for (let i = 0; i < tries; i++) {
    try {
      return await fn();
    } catch (err) {
      const status = (err as { status?: number }).status;
      const fatal = status === 400 || status === 401 || status === 403;
      if (fatal || i === tries - 1) {
        console.warn(`\n  ✗ ${label} : ${(err as Error).message}`);
        return null;
      }
      await new Promise((r) => setTimeout(r, 1500 * 2 ** i));
    }
  }
  return null;
}
