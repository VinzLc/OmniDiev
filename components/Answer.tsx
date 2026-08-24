"use client";

import { Fragment, cloneElement, isValidElement, type ReactElement, type ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

/**
 * Transforme les renvois « [3] » du texte en puces cliquables vers l'extrait.
 *
 * Le remplacement opère sur l'arbre React rendu plutôt que sur le markdown brut :
 * un « [3] » à l'intérieur d'un bloc de code ou d'un lien reste ainsi intact, et
 * le markdown n'a pas à être ré-analysé.
 */
function linkCitations(node: ReactNode, onPick: (n: number) => void, key = 0): ReactNode {
  if (typeof node === "string") {
    const parts = node.split(/(\[\d{1,2}\])/g);
    if (parts.length === 1) return node;
    return (
      <Fragment key={key}>
        {parts.map((part, i) => {
          const m = part.match(/^\[(\d{1,2})\]$/);
          if (!m) return part;
          const n = Number(m[1]);
          return (
            <button key={i} className="cite" onClick={() => onPick(n)} title={`Voir l'extrait ${n}`}>
              {n}
            </button>
          );
        })}
      </Fragment>
    );
  }

  if (Array.isArray(node)) return node.map((child, i) => linkCitations(child, onPick, i));

  if (isValidElement(node)) {
    const el = node as ReactElement<{ children?: ReactNode }>;
    if (el.type === "code" || el.props.children === undefined) return node;
    return cloneElement(el, undefined, linkCitations(el.props.children, onPick));
  }

  return node;
}

type Slot = { children?: ReactNode };

export function Answer({ text, onPick }: { text: string; onPick: (n: number) => void }) {
  const cite = (children: ReactNode) => linkCitations(children, onPick);

  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        p: ({ children }: Slot) => <p>{cite(children)}</p>,
        li: ({ children }: Slot) => <li>{cite(children)}</li>,
        h1: ({ children }: Slot) => <h2>{cite(children)}</h2>,
        h2: ({ children }: Slot) => <h2>{cite(children)}</h2>,
        h3: ({ children }: Slot) => <h3>{cite(children)}</h3>,
        h4: ({ children }: Slot) => <h3>{cite(children)}</h3>,
        td: ({ children }: Slot) => <td>{cite(children)}</td>,
        blockquote: ({ children }: Slot) => <blockquote>{cite(children)}</blockquote>,
        // Sans cible externe, un lien du modèle n'a nulle part où mener.
        a: ({ children }: Slot) => <>{cite(children)}</>,
      }}
    >
      {text}
    </ReactMarkdown>
  );
}
