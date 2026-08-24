"use client";

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";

type TreeRef = {
  id: string;
  name: string;
  gloss: string;
  size: number;
  sagas: number[];
  parents: number;
  children: number;
  spouses: number;
  siblings: number;
};

type Card = { id: string; name: string; gloss: string; kind: string; role: string };

type Tree = {
  id: string;
  name: string;
  gloss: string;
  rows: { label: string; people: Card[] }[];
  links: { from: string; to: string; nature?: string }[];
  counts: { parents: number; children: number; spouses: number; siblings: number };
};

const BASE = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

const fold = (s: string) =>
  s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();

const SAGA_SHORT: Record<number, string> = {
  1: "Émeraude", 2: "Héritiers", 3: "Antarès", 4: "Ashur-Sîn",
};

/** Segment orthogonal parent → enfant, tracé d'après les positions mesurées. */
type Wire = { d: string; key: string };

export function Genealogy() {
  const [index, setIndex] = useState<TreeRef[] | null>(null);
  const [query, setQuery] = useState("");
  const [saga, setSaga] = useState(0);
  const [openId, setOpenId] = useState<string | null>(null);
  const [tree, setTree] = useState<Tree | null>(null);
  const [wires, setWires] = useState<Wire[]>([]);

  const canvas = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetch(`${BASE}/genealogie/index.json`)
      .then((r) => r.json())
      .then((d) => setIndex(d.ready ? d.trees : []))
      .catch(() => setIndex([]));
    const id = new URLSearchParams(window.location.search).get("arbre");
    if (id) setOpenId(id);
  }, []);

  useEffect(() => {
    if (!openId) { setTree(null); setWires([]); return; }
    let cancelled = false;
    fetch(`${BASE}/genealogie/${openId}.json`)
      .then((r) => r.json())
      .then((d) => { if (!cancelled) setTree(d?.id ? d : null); })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [openId]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpenId(null); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  /*
   * Les traits sont calculés après le rendu, à partir des positions réelles des
   * cartes. Les déduire d'une mise en page théorique obligerait à réimplémenter
   * le placement du navigateur — et à le refaire à chaque changement de largeur.
   */
  useLayoutEffect(() => {
    if (!tree || !canvas.current) { setWires([]); return; }

    const measure = () => {
      const root = canvas.current;
      if (!root) return;
      const base = root.getBoundingClientRect();
      const at = (id: string) => {
        const el = root.querySelector(`[data-node="${id}"]`);
        if (!el) return null;
        const r = el.getBoundingClientRect();
        return {
          cx: r.left - base.left + r.width / 2 + root.scrollLeft,
          top: r.top - base.top + root.scrollTop,
          bottom: r.bottom - base.top + root.scrollTop,
        };
      };

      const next: Wire[] = [];
      for (const link of tree.links) {
        const a = at(link.from);
        const b = at(link.to);
        if (!a || !b || b.top <= a.bottom) continue;
        const mid = a.bottom + (b.top - a.bottom) / 2;
        next.push({
          key: `${link.from}>${link.to}`,
          d: `M ${a.cx} ${a.bottom} V ${mid} H ${b.cx} V ${b.top}`,
        });
      }
      setWires(next);
    };

    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(canvas.current);
    window.addEventListener("resize", measure);
    return () => { ro.disconnect(); window.removeEventListener("resize", measure); };
  }, [tree]);

  const shown = useMemo(() => {
    if (!index) return [];
    const q = fold(query.trim());
    return index.filter((t) => {
      if (saga && !t.sagas.includes(saga)) return false;
      if (!q) return true;
      return fold(t.name).includes(q) || fold(t.gloss).includes(q);
    });
  }, [index, query, saga]);

  const open = useCallback((id: string) => setOpenId(id), []);

  if (index && index.length === 0) {
    return (
      <div className="dex-empty">
        <p>
          Les arbres ne sont pas encore construits. Lancez <code>npm run genealogie</code>,
          puis redémarrez le serveur.
        </p>
      </div>
    );
  }

  return (
    <div className="dex">
      <div className="dex-bar">
        <input
          className="dex-search"
          value={query}
          placeholder="Chercher une personne…"
          onChange={(e) => setQuery(e.target.value)}
        />
        <div className="dex-filters">
          <button className={`chip saga${saga === 0 ? " on" : ""}`} onClick={() => setSaga(0)}>
            toutes
          </button>
          {[1, 2, 3, 4].map((s) => (
            <button
              key={s}
              className={`chip saga${saga === s ? " on" : ""}`}
              onClick={() => setSaga(s)}
            >
              {SAGA_SHORT[s]}
            </button>
          ))}
        </div>
        <span className="dex-count">
          {index ? (shown.length === index.length ? `${index.length} arbres` : `${shown.length} / ${index.length}`) : "…"}
        </span>
      </div>

      <div className="dex-body">
        <div className="dex-grid">
          {shown.map((t) => (
            <button key={t.id} className="gen-card" onClick={() => open(t.id)}>
              <span className="gen-name">{t.name}</span>
              <span className="dex-gloss">{t.gloss}</span>
              <span className="gen-counts">
                {t.parents > 0 && <em>{t.parents} parent{t.parents > 1 ? "s" : ""}</em>}
                {t.spouses > 0 && <em>{t.spouses} conjoint{t.spouses > 1 ? "s" : ""}</em>}
                {t.children > 0 && <em>{t.children} enfant{t.children > 1 ? "s" : ""}</em>}
                {t.siblings > 0 && <em>{t.siblings} dans la fratrie</em>}
              </span>
            </button>
          ))}
          {index && shown.length === 0 && <p className="dex-none">Aucun arbre ne correspond.</p>}
        </div>
      </div>

      {openId && (
        <div className="gen-overlay" onClick={() => setOpenId(null)}>
          <div className="gen-modal" onClick={(e) => e.stopPropagation()}>
            <header className="gen-modal-head">
              <div>
                <h2>{tree?.name ?? "…"}</h2>
                {tree?.gloss && <p>{tree.gloss}</p>}
              </div>
              <button className="dex-close" onClick={() => setOpenId(null)} title="Fermer (Échap)">
                ✕
              </button>
            </header>

            <div className="gen-canvas" ref={canvas}>
              {!tree && <span className="pulse"><i /><i /><i /></span>}

              {tree && (
                <>
                  <svg className="gen-wires" aria-hidden>
                    {wires.map((w) => (
                      <path key={w.key} d={w.d} />
                    ))}
                  </svg>

                  {tree.rows.map((row) => (
                    <div className="gen-row" key={row.label}>
                      <span className="gen-row-label">{row.label}</span>
                      <div className="gen-row-people">
                        {row.people.map((p) => (
                          <button
                            key={p.id}
                            data-node={p.id}
                            className={`gen-node${p.role ? ` ${p.role}` : ""}`}
                            onClick={() => open(p.id)}
                            title={p.gloss}
                          >
                            <span className="gen-node-name">{p.name}</span>
                            {p.role === "conjoint" && <span className="gen-tag">conjoint</span>}
                            {p.role === "fratrie" && <span className="gen-tag">fratrie</span>}
                          </button>
                        ))}
                      </div>
                    </div>
                  ))}
                </>
              )}
            </div>

            <footer className="gen-modal-foot">
              Chaque personne ouvre son propre arbre. Deux générations de part et d&apos;autre
              sont montrées — au-delà, les alliances relient tout le monde et l&apos;arbre
              cesse d&apos;être lisible.
            </footer>
          </div>
        </div>
      )}
    </div>
  );
}
