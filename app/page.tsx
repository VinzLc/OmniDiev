"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Sigil } from "@/components/Sigil";
import { Answer } from "@/components/Answer";
import { Sources, type CodexHit, type SourceHit } from "@/components/Sources";
import { Codex } from "@/components/Codex";

const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];

/** Valeur d'attente, le temps que /api/status réponde. */
const SAGAS_FALLBACK = 3;

/**
 * Le nombre en toutes lettres, pour la prose.
 * « Les trois épopées » se lit mieux que « Les 3 épopées » ; au-delà de neuf,
 * le chiffre reprend ses droits.
 */
const MOTS = ["zéro", "une", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf"];
const enLettres = (n: number) => MOTS[n] ?? String(n);

type Turn = {
  role: "user" | "oracle";
  text: string;
  thinking: string;
  hits: SourceHit[];
  codex: CodexHit[];
  error?: string;
  done: boolean;
};

type BookRef = { id: string; saga: number; tome: number; order: number; title: string; year: number; short: string };

type Status = {
  ready: boolean;
  auth: { ready: boolean; source: string | null; label: string; warning?: string };
  model: string;
  sagas: { id: number; name: string; short: string; books: number }[];
  books: BookRef[];
  corpus: { chunks: number; pages: number; terms: number } | null;
  semantic: { model: string; count: number } | null;
  codex: { entries: number; chapters: number } | null;
};

const SUGGESTIONS = [
  { kicker: "Personnage", q: "Qui est Onyx, et pourquoi est-il à la fois héros et menace ?" },
  { kicker: "D'une épopée à l'autre", q: "Que devient Kira entre la fin des Chevaliers d'Émeraude et les Héritiers d'Enkidiev ?" },
  { kicker: "Chronologie", q: "Retrace la guerre contre Amecareth, tome par tome." },
  { kicker: "Univers", q: "Qu'est-ce qu'Alnilam, et comment se compare-t-il à Enkidiev ?" },
];

const blank = (role: Turn["role"], text = ""): Turn => ({
  role, text, thinking: "", hits: [], codex: [], done: false,
});

export default function Page() {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<Status | null>(null);
  // Position absolue du dernier tome lu, sur les 24 : 0 signifie « tout lu ».
  const [maxOrder, setMaxOrder] = useState<number>(0);
  const [focus, setFocus] = useState<number | null>(null);
  const [tab, setTab] = useState<"oracle" | "codex">("oracle");

  const abort = useRef<AbortController | null>(null);
  const thread = useRef<HTMLDivElement>(null);
  const field = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    fetch("/api/status").then((r) => r.json()).then(setStatus).catch(() => setStatus(null));
  }, []);


  useEffect(() => {
    thread.current?.scrollTo({ top: thread.current.scrollHeight, behavior: "smooth" });
  }, [turns.length]);

  const grow = useCallback(() => {
    const el = field.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = Math.min(el.scrollHeight, 190) + "px";
  }, []);

  const ask = useCallback(
    async (question: string) => {
      const q = question.trim();
      if (!q || busy) return;

      setDraft("");
      setFocus(null);
      setBusy(true);
      requestAnimationFrame(grow);

      // Un tour vide (erreur, ou interruption avant le premier mot) ferait
      // échouer la requête : l'API refuse un bloc de texte vide.
      const history = turns
        .filter((t) => !t.error && t.text.trim())
        .map((t) => ({ role: t.role === "oracle" ? ("assistant" as const) : ("user" as const), content: t.text }));

      setTurns((prev) => [...prev, { ...blank("user", q), done: true }, blank("oracle")]);

      const controller = new AbortController();
      abort.current = controller;

      // Met à jour le dernier tour, celui de l'Oracle.
      const patch = (fn: (t: Turn) => Turn) =>
        setTurns((prev) => prev.map((t, i) => (i === prev.length - 1 ? fn(t) : t)));

      try {
        const res = await fetch("/api/chat", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ question: q, history, maxOrder: maxOrder || null }),
          signal: controller.signal,
        });

        if (!res.ok || !res.body) {
          const j = await res.json().catch(() => ({ error: `Erreur ${res.status}` }));
          patch((t) => ({ ...t, error: j.error ?? `Erreur ${res.status}`, done: true }));
          return;
        }

        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });

          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";

          for (const raw of lines) {
            if (!raw.trim()) continue;
            let ev: Record<string, string & unknown[]>;
            try { ev = JSON.parse(raw); } catch { continue; }

            switch (ev.type) {
              case "sources":
                patch((t) => ({ ...t, hits: ev.hits as unknown as SourceHit[], codex: ev.codex as unknown as CodexHit[] }));
                break;
              case "text":
                patch((t) => ({ ...t, text: t.text + ev.text }));
                break;
              case "thinking":
                patch((t) => ({ ...t, thinking: t.thinking + ev.text }));
                break;
              case "error":
                patch((t) => ({ ...t, error: String(ev.message), done: true }));
                break;
              case "done":
                patch((t) => ({ ...t, done: true }));
                break;
            }
          }
        }
      } catch (err) {
        if ((err as Error).name !== "AbortError") {
          patch((t) => ({ ...t, error: (err as Error).message, done: true }));
        }
      } finally {
        patch((t) => ({ ...t, done: true }));
        setBusy(false);
        abort.current = null;
      }
    },
    [busy, grow, maxOrder, turns],
  );

  // Liens profonds : /?q=… pose la question au chargement, /?tab=codex ouvre
  // directement le recueil. Une interrogation devient ainsi partageable.
  const opened = useRef(false);
  useEffect(() => {
    if (opened.current) return;
    opened.current = true;
    const params = new URLSearchParams(window.location.search);
    if (params.get("tab") === "codex" || params.get("fiche")) setTab("codex");
    const q = params.get("q");
    if (q?.trim()) void ask(q);
    // `ask` change à chaque rendu ; le garde-fou ci-dessus suffit à n'ouvrir
    // la conversation qu'une fois.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ask]);

  const last = turns.at(-1);
  const shown = last?.role === "oracle" ? last : null;
  const notReady = status && (!status.ready || !status.auth.ready);

  return (
    <div className="shell">
      <header className="masthead">
        <div className="brand">
          <Sigil className="sigil" />
          <h1>L&apos;Oracle d&apos;Émeraude</h1>
          <span className="tagline">
            Anne Robillard · {status?.sagas.length ?? SAGAS_FALLBACK} épopées
          </span>
        </div>

        <nav className="tabs" role="tablist">
          <button
            role="tab"
            aria-selected={tab === "oracle"}
            className={tab === "oracle" ? "on" : ""}
            onClick={() => setTab("oracle")}
          >
            Oracle
          </button>
          <button
            role="tab"
            aria-selected={tab === "codex"}
            className={tab === "codex" ? "on" : ""}
            onClick={() => setTab("codex")}
          >
            Codex
            {status?.codex && <span className="tab-badge">{status.codex.entries}</span>}
          </button>
        </nav>

        <div className="spacer" />

        <div className="spoiler">
          <svg className="shield" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden>
            <path d="M8 1.5 13.5 3.5v4.2c0 3.2-2.2 5.6-5.5 6.8-3.3-1.2-5.5-3.6-5.5-6.8V3.5L8 1.5Z" strokeLinejoin="round" />
          </svg>
          <label htmlFor="maxOrder">J&apos;ai lu jusqu&apos;à</label>
          <select id="maxOrder" value={maxOrder} onChange={(e) => setMaxOrder(Number(e.target.value))}>
            {/* Libellé déduit du catalogue : « deux épopées » était devenu faux
                le jour où la troisième est arrivée. */}
            <option value={0}>
              Tout — les {enLettres(status?.sagas.length ?? SAGAS_FALLBACK)} épopées
            </option>
            {status?.sagas.map((sg) => (
              <optgroup key={sg.id} label={sg.name}>
                {status.books
                  .filter((b) => b.saga === sg.id)
                  .map((b) => (
                    <option key={b.order} value={b.order}>
                      {b.tome === 0 ? "Hors-série" : `Tome ${ROMAN[b.tome]}`} — {b.title}
                    </option>
                  ))}
              </optgroup>
            ))}
          </select>
        </div>

        {status?.corpus && (
          <div className="stat">
            <span>
              <b>{status.books.length}</b> tomes ·{" "}
              <b>{status.corpus.pages.toLocaleString("fr-FR")}</b> pages indexées
            </span>
            <span>
              <b>{status.corpus.chunks.toLocaleString("fr-FR")}</b> fragments
              {status.codex ? ` · ${status.codex.entries} fiches` : ""}
            </span>
          </div>
        )}
      </header>

      {tab === "codex" ? (
        <Codex maxOrder={maxOrder} />
      ) : (
      <div className="workspace">
        <div className="column">
          <div className={`thread${turns.length === 0 ? " empty" : ""}`} ref={thread}>
            {turns.length === 0 ? (
              <div className="welcome">
                <Sigil className="crest" />
                <h2>Posez votre question sur la saga.</h2>
                <p className="lede">
                  Les {enLettres(status?.sagas.length ?? SAGAS_FALLBACK)} épopées
                  d&apos;Anne Robillard sont indexées page à page —{" "}
                  {status?.corpus?.pages.toLocaleString("fr-FR") ?? "12 181"} pages,
                  une seule histoire.
                  Chaque réponse s&apos;appuie sur des passages retrouvés dans les livres, et vous
                  pouvez ouvrir chacun d&apos;eux pour vérifier.
                </p>

                {notReady && (
                  <div className={`notice ${status?.ready ? "" : "error"}`}>
                    {!status?.ready && (
                      <>
                        L&apos;index n&apos;est pas encore construit. Lancez <code>npm run ingest</code> à la
                        racine du projet.
                        <br />
                      </>
                    )}
                    {!status?.auth.ready && (
                      <>
                        Aucun identifiant Anthropic. Deux possibilités, puis redémarrez le serveur :
                        <br />
                        — une clé : copiez <code>.env.example</code> vers <code>.env.local</code> et
                        renseignez <code>ANTHROPIC_API_KEY</code> ;
                        <br />
                        — un compte : <code>brew install anthropics/tap/ant</code> puis{" "}
                        <code>ant auth login</code>.
                      </>
                    )}
                  </div>
                )}

                <div className="suggestions">
                  {SUGGESTIONS.map((s) => (
                    <button key={s.q} className="suggestion" onClick={() => ask(s.q)}>
                      <span className="kicker">{s.kicker}</span>
                      {s.q}
                    </button>
                  ))}
                </div>
              </div>
            ) : (
              <div className="thread-inner">
                {turns.map((t, i) => (
                  <div className={`turn ${t.role}`} key={i}>
                    <div className="turn-label">
                      <span className="dot" />
                      {t.role === "user" ? "Vous" : "L'Oracle"}
                    </div>

                    {t.role === "user" ? (
                      <div className="body">{t.text}</div>
                    ) : (
                      <>
                        {t.thinking && (
                          <details className="musing">
                            <summary>
                              {t.done ? "Cheminement de l'Oracle" : "L'Oracle consulte ses archives…"}
                            </summary>
                            <div className="inner">{t.thinking}</div>
                          </details>
                        )}

                        {t.error ? (
                          <div className="notice error">{t.error}</div>
                        ) : (
                          <div className="body">
                            {t.text ? (
                              <Answer text={t.text} onPick={setFocus} />
                            ) : (
                              <span className="pulse">
                                <i /><i /><i />
                              </span>
                            )}
                            {!t.done && t.text && <span className="caret" />}
                          </div>
                        )}
                      </>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="composer-wrap">
            <div className="composer-inner">
              <div className="composer">
                <textarea
                  ref={field}
                  rows={1}
                  value={draft}
                  placeholder="Une question sur la saga d'Anne Robillard…"
                  onChange={(e) => { setDraft(e.target.value); grow(); }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !e.shiftKey) {
                      e.preventDefault();
                      ask(draft);
                    }
                  }}
                />
                {busy ? (
                  <button className="send stop" onClick={() => abort.current?.abort()} title="Interrompre">
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor">
                      <rect x="1" y="1" width="10" height="10" rx="2" />
                    </svg>
                  </button>
                ) : (
                  <button className="send" disabled={!draft.trim()} onClick={() => ask(draft)} title="Envoyer">
                    <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M8 13V3M3.5 7.5 8 3l4.5 4.5" />
                    </svg>
                  </button>
                )}
              </div>

              <div className="composer-foot">
                <span>
                  <kbd>Entrée</kbd> pour envoyer · <kbd>Maj</kbd>+<kbd>Entrée</kbd> pour aller à la ligne
                </span>
                <span className="spacer" />
                {maxOrder > 0 && (
                  <span>
                    Réponses limitées à ce qui précède «{" "}
                    {status?.books.find((b) => b.order === maxOrder)?.title} » inclus
                  </span>
                )}
                {status?.model && maxOrder === 0 && (
                  <span title={status.auth.label}>{status.model}</span>
                )}
              </div>
            </div>
          </div>
        </div>

        <Sources
          hits={shown?.hits ?? []}
          codex={shown?.codex ?? []}
          focus={focus}
          sagaNames={Object.fromEntries((status?.sagas ?? []).map((s) => [s.id, s.short]))}
        />
      </div>
      )}
    </div>
  );
}
