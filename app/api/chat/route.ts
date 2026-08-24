import Anthropic from "@anthropic-ai/sdk";
import { search } from "@/lib/retrieve.ts";
import { searchCodex, expandQuery, codexForPassages, mergeCodexHits } from "@/lib/codex.ts";
import { systemFor, buildUserContent, historyText } from "@/lib/prompt.ts";
import { credentials } from "@/lib/credentials.ts";

export const runtime = "nodejs";
export const maxDuration = 300;

const MODEL = process.env.OMNIDIEV_MODEL ?? "claude-opus-5";
const EFFORT = (process.env.OMNIDIEV_EFFORT ?? "medium") as "low" | "medium" | "high" | "xhigh" | "max";

type Turn = { role: "user" | "assistant"; content: string };

type Body = {
  question: string;
  history?: Turn[];
  /**
   * Limite anti-divulgation : position absolue du dernier tome lu (1 à 24).
   * Rien au-delà ne doit être ni cherché, ni révélé.
   */
  maxOrder?: number | null;
};

const encoder = new TextEncoder();

export async function POST(req: Request) {
  const { question, history = [], maxOrder = null }: Body = await req.json();

  if (!question?.trim()) {
    return Response.json({ error: "Question vide." }, { status: 400 });
  }
  // On n'exige pas de clé API : un profil OAuth déposé par `ant auth login`
  // suffit, et le client nu ci-dessous le trouvera tout seul.
  const cred = credentials();
  if (!cred.source) {
    return Response.json(
      {
        error:
          "Aucun identifiant Anthropic. Renseignez ANTHROPIC_API_KEY dans .env.local, " +
          "ou connectez un profil avec `ant auth login`.",
      },
      { status: 500 },
    );
  }
  if (cred.warning) console.warn(cred.warning);

  const client = new Anthropic();

  const stream = new ReadableStream({
    async start(controller) {
      const send = (o: unknown) => controller.enqueue(encoder.encode(JSON.stringify(o) + "\n"));

      try {
        // — Récupération ————————————————————————————————
        const hits = await search(expandQuery(question), { limit: 14, maxOrder });
        // Les fiches viennent de deux côtés : ce que la question nomme, et ce
        // que les extraits font ressortir. Le second compte autant : une
        // question sur Farrell ramène surtout des passages sur Swan, dont
        // l'identité doit être fournie sous peine d'être inventée.
        const codexHits = mergeCodexHits(
          searchCodex(question, 4, maxOrder ?? undefined),
          codexForPassages(hits.map((h) => h.chunk.text), 4, maxOrder ?? undefined),
          6,
        );

        send({
          type: "sources",
          hits: hits.map((h, i) => ({
            n: i + 1,
            ref: h.chunk.ref,
            saga: h.chunk.saga,
            tome: h.chunk.tome,
            bookTitle: h.chunk.bookTitle,
            chapter: h.chunk.chapterLabel,
            pageStart: h.chunk.pageStart,
            pageEnd: h.chunk.pageEnd,
            via: h.via,
            text: h.chunk.text,
          })),
          codex: codexHits.map((h) => ({
            name: h.entry.name,
            kind: h.entry.kind,
            gloss: h.entry.gloss,
            books: h.entry.books,
          })),
        });

        // — Génération ————————————————————————————————
        const priorTurns: Anthropic.MessageParam[] = history.slice(-6).map((t) => ({
          role: t.role,
          content: historyText(t.content),
        }));

        let emitted = false;

        const runOnce = async (useCitations: boolean) => {
          const ms = client.messages.stream({
            model: MODEL,
            max_tokens: 16000,
            system: systemFor(maxOrder, useCitations),
            thinking: { type: "adaptive", display: "summarized" },
            output_config: { effort: EFFORT },
            messages: [
              ...priorTurns,
              { role: "user", content: buildUserContent(question, hits, codexHits, useCitations) },
            ],
          });

          // Claude découpe sa réponse en blocs de texte ; un bloc étayé porte
          // ses citations. On les accumule par bloc et on écrit les puces à sa
          // fermeture : c'est la fin du passage, là où un lecteur attend
          // l'appel de note. Les citations arrivent avant le texte qu'elles
          // appuient, les émettre au fil de l'eau les placerait en amont.
          let blockIsText = false;
          let blockRefs: number[] = [];

          for await (const event of ms) {
            switch (event.type) {
              case "content_block_start":
                blockIsText = event.content_block.type === "text";
                blockRefs = [];
                break;

              case "content_block_delta": {
                const d = event.delta;
                if (d.type === "text_delta") { emitted = true; send({ type: "text", text: d.text }); }
                else if (d.type === "thinking_delta") { emitted = true; send({ type: "thinking", text: d.thinking }); }
                else if (d.type === "citations_delta") {
                  send({ type: "citation", citation: d.citation });
                  const title = (d.citation as { document_title?: string | null }).document_title ?? "";
                  const n = Number(title.match(/^\[(\d{1,2})\]/)?.[1]);
                  if (n && !blockRefs.includes(n)) blockRefs.push(n);
                }
                break;
              }

              case "content_block_stop":
                if (blockIsText && blockRefs.length) {
                  send({ type: "text", text: blockRefs.map((n) => `[${n}]`).join("") });
                }
                blockIsText = false;
                blockRefs = [];
                break;
            }
          }
          return ms.finalMessage();
        };

        let citationsOn = true;
        let final: Anthropic.Message;
        try {
          final = await runOnce(true);
        } catch (err) {
          // Un refus de validation survient avant tout contenu : le repli sans
          // citations est alors sûr, il ne peut pas dupliquer la réponse.
          if (err instanceof Anthropic.BadRequestError && !emitted) {
            console.warn("Citations refusées par l'API, repli sans citations :", err.message);
            citationsOn = false;
            final = await runOnce(false);
          } else {
            throw err;
          }
        }

        send({
          type: "done",
          citationsOn,
          model: MODEL,
          usage: { input: final.usage.input_tokens, output: final.usage.output_tokens },
          stopReason: final.stop_reason,
        });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error("Erreur de génération :", err);
        send({ type: "error", message });
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "application/x-ndjson; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
    },
  });
}
