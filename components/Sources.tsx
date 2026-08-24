"use client";

import { useEffect, useRef } from "react";

export type SourceHit = {
  n: number;
  ref: string;
  saga: number;
  tome: number;
  bookTitle: string;
  chapter: string;
  pageStart: number;
  pageEnd: number;
  via: string[];
  text: string;
};

export type CodexHit = { name: string; kind: string; gloss: string; books: number[] };

const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];

/*
 * Les noms courts d'épopée viennent de /api/status, jamais d'une table écrite
 * ici : le catalogue de lib/books.ts en est l'unique source, et une copie locale
 * finirait par mentir dès l'épopée suivante.
 */

export function Sources({
  hits,
  codex,
  focus,
  sagaNames,
}: {
  hits: SourceHit[];
  codex: CodexHit[];
  /** Numéro d'extrait à mettre en avant, piloté par les puces de citation. */
  focus: number | null;
  /** Noms courts d'épopée, par identifiant. */
  sagaNames: Record<number, string>;
}) {
  const body = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (focus == null) return;
    const el = body.current?.querySelector(`#extrait-${focus}`) as HTMLDetailsElement | null;
    if (!el) return;
    el.open = true;
    el.scrollIntoView({ behavior: "smooth", block: "center" });
    el.classList.add("flash");
    const t = setTimeout(() => el.classList.remove("flash"), 1600);
    return () => clearTimeout(t);
  }, [focus]);

  return (
    <aside className="aside">
      <div className="aside-head">
        <span>Sources</span>
        {hits.length > 0 && <span className="count">{hits.length}</span>}
      </div>

      <div className="aside-body" ref={body}>
        {hits.length === 0 && codex.length === 0 && (
          <p style={{ color: "var(--text-faint)", fontSize: 13, margin: "6px 2px" }}>
            Les passages consultés pour répondre s'afficheront ici, avec leur tome,
            leur chapitre et leur page.
          </p>
        )}

        {codex.map((c) => (
          <div className="codex-card" key={c.name}>
            <div className="kind">{c.kind}</div>
            <div className="name">{c.name}</div>
            <div className="gloss">{c.gloss}</div>
          </div>
        ))}

        {hits.map((h) => {
          const pages = h.pageStart === h.pageEnd ? `p. ${h.pageStart}` : `p. ${h.pageStart}-${h.pageEnd}`;
          return (
            <details className="source" id={`extrait-${h.n}`} key={h.n}>
              <summary>
                <span className="num">{h.n}</span>
                <span className="where">
                  <span className="tome">
                    {sagaNames[h.saga] ?? `Épopée ${h.saga}`}{" "}
                    {h.tome === 0 ? "hors-série" : ROMAN[h.tome]} — {h.bookTitle}
                  </span>
                  <span className="meta">
                    {h.chapter} · {pages}
                  </span>
                  <span style={{ display: "block", marginTop: 5 }}>
                    {h.via.includes("lexical") && <span className="tag lex">lexical</span>}
                    {h.via.includes("sémantique") && <span className="tag sem">sémantique</span>}
                  </span>
                </span>
              </summary>
              <div className="excerpt">{h.text}</div>
            </details>
          );
        })}

        {hits.length > 0 && (
          <p className="legend">
            Chaque puce de la réponse ouvre l&apos;extrait correspondant. Une affirmation
            sans puce n&apos;est appuyée par aucun passage retrouvé — c&apos;est là qu&apos;il
            faut regarder de près.
          </p>
        )}
      </div>
    </aside>
  );
}
