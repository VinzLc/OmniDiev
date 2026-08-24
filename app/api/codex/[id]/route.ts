import { loadCodex } from "@/lib/codex.ts";
import { bookAt, bookLabel, ROMAN, sagaOf } from "@/lib/books.ts";
import { fold } from "@/lib/text.ts";

export const runtime = "nodejs";

/** Fiche complète, plus la résolution des renvois vers d'autres fiches. */
export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const l = loadCodex();
  const entry = l?.codex.entries.find((e) => e.id === id);
  if (!entry) return Response.json({ error: "Fiche inconnue." }, { status: 404 });

  // Un lien ne vaut que s'il mène quelque part : on ne rend cliquables que les
  // relations qui correspondent à une fiche existante.
  const byName = new Map(l!.codex.entries.map((e) => [fold(e.name), e.id]));
  for (const e of l!.codex.entries) {
    for (const a of e.aliases) if (!byName.has(fold(a))) byName.set(fold(a), e.id);
  }

  return Response.json({
    ...entry,
    volumes: entry.books.map((o) => {
      const b = bookAt(o);
      return {
        order: o,
        saga: b.saga,
        sagaShort: sagaOf(b.saga).short,
        label: b.tome === 0 ? "Hors-série" : ROMAN[b.tome],
        full: bookLabel(b),
      };
    }),
    relations: entry.relations.map((r) => ({
      ...r,
      target: byName.get(fold(r.name)) ?? null,
    })),
  });
}
