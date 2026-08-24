"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

type Entry = {
  n: number;
  id: string;
  name: string;
  kind: string;
  gloss: string;
  books: number[];
  sagas: number[];
  aliases: number;
  relations: number;
  first: number;
  firstSaga: string;
};

type SagaRef = { id: number; name: string; short: string; from: number; to: number };

type Index = {
  ready: boolean;
  entries: Entry[];
  sagas: SagaRef[];
  books: { order: number; saga: number; label: string; title: string }[];
};

type Detail = {
  id: string;
  name: string;
  kind: string;
  aliases: string[];
  gloss: string;
  description: string;
  arc: string;
  firstSeen: string;
  volumes: { order: number; saga: number; sagaShort: string; label: string; full: string }[];
  relations: { name: string; nature: string; target: string | null }[];
};

const KINDS = ["personnage", "lieu", "peuple", "objet", "concept", "événement"];

const fold = (s: string) =>
  s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();

export function Codex({ maxOrder }: { maxOrder: number }) {
  const [index, setIndex] = useState<Index | null>(null);
  const [query, setQuery] = useState("");
  const [kinds, setKinds] = useState<Set<string>>(new Set());
  const [saga, setSaga] = useState<number>(0);
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [loading, setLoading] = useState(false);

  const grid = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetch("/api/codex").then((r) => r.json()).then(setIndex).catch(() => setIndex(null));
    // Lien direct vers une fiche : /?fiche=sierra
    const id = new URLSearchParams(window.location.search).get("fiche");
    if (id) setSelected(id);
  }, []);

  // Le détail est chargé à la demande ; une sélection rapide annule la précédente.
  useEffect(() => {
    if (!selected) { setDetail(null); return; }
    let cancelled = false;
    setLoading(true);
    fetch(`/api/codex/${selected}`)
      .then((r) => r.json())
      .then((d) => { if (!cancelled) { setDetail(d.error ? null : d); setLoading(false); } })
      .catch(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [selected]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setSelected(null); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const shown = useMemo(() => {
    if (!index?.entries) return [];
    const q = fold(query.trim());
    return index.entries.filter((e) => {
      // Limite de lecture : une fiche dont l'entrée en scène est encore à venir
      // n'a rien à faire dans le recueil.
      if (maxOrder && e.first > maxOrder) return false;
      if (kinds.size && !kinds.has(e.kind)) return false;
      if (saga && !e.sagas.includes(saga)) return false;
      if (!q) return true;
      return fold(e.name).includes(q) || fold(e.gloss).includes(q);
    });
  }, [index, query, kinds, saga, maxOrder]);

  const toggleKind = useCallback((k: string) => {
    setKinds((prev) => {
      const next = new Set(prev);
      if (next.has(k)) next.delete(k); else next.add(k);
      return next;
    });
  }, []);

  const open = useCallback((id: string) => setSelected(id), []);

  // Amener la carte choisie dans la vue — après le rendu, car sur un lien
  // direct (/?fiche=onyx) la grille n'existe pas encore au moment du choix.
  useEffect(() => {
    if (!selected) return;
    grid.current
      ?.querySelector(`[data-id="${selected}"]`)
      ?.scrollIntoView({ block: "center" });
  }, [selected, index]);

  if (index && !index.ready) {
    return (
      <div className="dex-empty">
        <p>
          Le Codex n&apos;est pas encore construit. Lancez <code>npm run codex</code> à la
          racine du projet, puis redémarrez le serveur.
        </p>
      </div>
    );
  }

  const total = index?.entries.length ?? 0;

  return (
    <div className={`dex${selected ? " open" : ""}`}>
      <div className="dex-bar">
        <input
          className="dex-search"
          value={query}
          placeholder="Chercher un nom, un rôle…"
          onChange={(e) => setQuery(e.target.value)}
        />

        <div className="dex-filters">
          {KINDS.filter((k) => index?.entries.some((e) => e.kind === k)).map((k) => (
            <button
              key={k}
              className={`chip k-${fold(k)}${kinds.has(k) ? " on" : ""}`}
              onClick={() => toggleKind(k)}
            >
              {k}
            </button>
          ))}
        </div>

        <div className="dex-filters">
          <button className={`chip saga${saga === 0 ? " on" : ""}`} onClick={() => setSaga(0)}>
            toutes
          </button>
          {index?.sagas.map((s) => (
            <button
              key={s.id}
              className={`chip saga${saga === s.id ? " on" : ""}`}
              onClick={() => setSaga(s.id)}
              title={s.name}
            >
              {s.short}
            </button>
          ))}
        </div>

        <span className="dex-count">
          {shown.length === total ? `${total} fiches` : `${shown.length} / ${total}`}
        </span>
      </div>

      <div className="dex-body">
        <div className="dex-grid" ref={grid}>
          {shown.map((e) => (
            <button
              key={e.id}
              data-id={e.id}
              className={`dex-card k-${fold(e.kind)}${selected === e.id ? " active" : ""}`}
              onClick={() => open(e.id)}
            >
              <span className="dex-num">{String(e.n).padStart(3, "0")}</span>
              <span className="dex-kind">{e.kind}</span>
              <span className="dex-name">{e.name}</span>
              <span className="dex-gloss">{e.gloss}</span>
              <span className="dex-foot">
                <span className="dex-dots">
                  {/* Une pastille par épopée existante, pas par épopée supposée. */}
                  {(index?.sagas ?? []).map((s) => (
                    <i key={s.id} className={e.sagas.includes(s.id) ? `on s${s.id}` : ""} />
                  ))}
                </span>
                {e.books.length} vol.
              </span>
            </button>
          ))}

          {shown.length === 0 && (
            <p className="dex-none">
              Aucune fiche ne correspond{maxOrder ? " dans les volumes que vous avez lus" : ""}.
            </p>
          )}
        </div>

        {selected && (
          <aside className="dex-detail">
            <button className="dex-close" onClick={() => setSelected(null)} title="Fermer (Échap)">
              ✕
            </button>

            {loading && !detail && <span className="pulse"><i /><i /><i /></span>}

            {detail && (
              <>
                <div className="dex-detail-head">
                  <span className="dex-num big">
                    {String(shown.find((e) => e.id === detail.id)?.n ?? 0).padStart(3, "0")}
                  </span>
                  <div>
                    <h2>{detail.name}</h2>
                    <span className={`chip k-${fold(detail.kind)} on`}>{detail.kind}</span>
                  </div>
                </div>

                {detail.aliases.length > 0 && (
                  <p className="dex-aliases">Aussi appelé : {detail.aliases.join(" · ")}</p>
                )}

                <p className="dex-lead">{detail.gloss}</p>

                <h3>Description</h3>
                <p>{detail.description}</p>

                {detail.arc && (
                  <>
                    <h3>Évolution</h3>
                    <p>{detail.arc}</p>
                  </>
                )}

                {detail.relations.length > 0 && (
                  <>
                    <h3>Liens</h3>
                    <ul className="dex-rel">
                      {detail.relations.map((r, i) => (
                        <li key={i}>
                          {r.target ? (
                            <button className="dex-link" onClick={() => open(r.target!)}>
                              {r.name}
                            </button>
                          ) : (
                            <span className="dex-link off">{r.name}</span>
                          )}
                          <span className="dex-nature">{r.nature}</span>
                        </li>
                      ))}
                    </ul>
                  </>
                )}

                <h3>Apparitions</h3>
                <div className="dex-vols">
                  {detail.volumes
                    .filter((v) => !maxOrder || v.order <= maxOrder)
                    .map((v) => (
                      <span key={v.order} className={`vol s${v.saga}`} title={v.full}>
                        {v.sagaShort} {v.label}
                      </span>
                    ))}
                </div>
                <p className="dex-first">Première apparition — {detail.firstSeen}</p>

                {maxOrder > 0 && (
                  <p className="dex-warn">
                    Cette fiche synthétise l&apos;ensemble de la saga : sa description et son
                    évolution peuvent déborder les volumes que vous avez lus.
                  </p>
                )}
              </>
            )}
          </aside>
        )}
      </div>
    </div>
  );
}
