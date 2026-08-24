import fs from "node:fs";
import path from "node:path";
import { codexStats } from "@/lib/codex.ts";
import { BOOKS, SAGAS, bookId, shortLabel } from "@/lib/books.ts";
import { credentials } from "@/lib/credentials.ts";

export const runtime = "nodejs";

export async function GET() {
  const dir = path.join(process.cwd(), "data", "index");
  const read = (f: string) => {
    const p = path.join(dir, f);
    return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : null;
  };

  const manifest = read("manifest.json");
  const embeddings = read("embeddings.json");

  return Response.json({
    ready: Boolean(manifest),
    auth: (() => { const c = credentials(); return { ready: Boolean(c.source), source: c.source, label: c.label, warning: c.warning }; })(),
    model: process.env.OMNIDIEV_MODEL ?? "claude-opus-5",
    sagas: SAGAS.map((s) => ({
      id: s.id,
      name: s.name,
      short: s.short,
      books: BOOKS.filter((b) => b.saga === s.id).length,
    })),
    books: BOOKS.map((b) => ({
      id: bookId(b),
      saga: b.saga,
      tome: b.tome,
      order: b.order,
      title: b.title,
      year: b.year,
      short: shortLabel(b),
    })),
    corpus: manifest && {
      chunks: manifest.chunks,
      terms: manifest.terms,
      builtAt: manifest.builtAt,
      pages: manifest.books.reduce((s: number, b: { pages: number }) => s + b.pages, 0),
      perBook: manifest.books,
    },
    semantic: embeddings && { model: embeddings.model, dim: embeddings.dim, count: embeddings.count },
    codex: codexStats(),
  });
}
