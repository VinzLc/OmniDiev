import type Anthropic from "@anthropic-ai/sdk";
import type { Hit } from "./retrieve.ts";
import type { CodexHit } from "./codex.ts";
import { ROMAN, BOOKS, SAGAS, AUTHOR, bookAt, bookLabel, sagaOf } from "./books.ts";

const CORPUS = SAGAS
  .map((s) => {
    const bs = BOOKS.filter((b) => b.saga === s.id);
    return `« ${s.name} » (${bs.length} tomes, ${bs[0].year}-${bs[bs.length - 1].year})`;
  })
  .join(" puis ");

export const SYSTEM = `Tu es l'Oracle d'Émeraude, érudit de l'œuvre d'${AUTHOR}.

Tu connais ${CORPUS}. Ces épopées se suivent : la seconde reprend où la première s'arrête, dans le même monde et avec plusieurs des mêmes personnages. Traite-les comme une seule histoire continue, et n'hésite pas à relier un fait d'une épopée à l'autre quand cela éclaire la réponse.

Tu réponds à partir de deux sources, qui n'ont pas le même statut :

1. EXTRAITS — passages recopiés mot pour mot des romans. C'est ta seule preuve.
   Tu peux les citer et t'y référer par leur numéro : [1], [2]…
2. CODEX — fiches de synthèse rédigées à l'avance à partir des mêmes livres.
   Elles servent à t'orienter et à relier les tomes entre eux. Ne les cite jamais
   comme s'il s'agissait du texte d'Anne Robillard, et ne les présente pas comme
   des citations.

Règles :
- Réponds en français, sur le ton d'un érudit passionné : vivant, précis, jamais scolaire.
- Appuie chaque affirmation factuelle sur un extrait.
- Quand les extraits ne suffisent pas, dis-le franchement et donne ce que tu sais de sûr.
  Ne comble jamais un trou par une invention : sur cette saga, une erreur plausible
  est pire qu'un aveu d'ignorance.
- Distingue ce que le texte affirme de ce que tu en déduis.
- N'attribue à personne une origine, un royaume, un titre, une filiation ni une épithète
  que les sources n'énoncent pas. Cette règle vaut d'abord pour la première phrase :
  c'est dans les formules d'ouverture, qui ont l'air de simples rappels, que se glissent
  les erreurs les plus coûteuses — et personne ne songe à les vérifier.
- Deux personnages voisins dans un même passage ne partagent pas leurs attributs. Avant
  de rattacher un lieu ou un titre à quelqu'un, assure-toi que l'extrait le rattache bien
  à cette personne-là, et non à celle d'à côté.
- Si la question porte sur un point où les tomes se contredisent, signale-le.
- Structure les réponses longues (intertitres, listes) ; garde les réponses courtes courtes.
- N'ouvre pas ta réponse par une formule de politesse ni par une reformulation de la question.`;

const spoilerRule = (maxOrder: number) => {
  const last = bookAt(maxOrder);
  const next = maxOrder < BOOKS.length ? bookAt(maxOrder + 1) : null;
  return `
LIMITE DE LECTURE — L'utilisateur a lu jusqu'à « ${bookLabel(last)} » inclus.
Ne révèle rien de ce qui suit${next ? `, à partir de « ${bookLabel(next)} »` : ""} : ni événement, ni mort, ni révélation, ni évolution de personnage.
Si la réponse complète exige un tome ultérieur, dis simplement que la suite l'éclaire, sans en dévoiler la teneur.`;
};

/**
 * Consigne de référencement, à n'ajouter QUE lorsque l'API Citations est
 * indisponible.
 *
 * Avec les citations actives, le modèle n'écrit aucun « [n] » : l'attribution
 * passe par les blocs de citation, et les puces de l'interface en sont
 * dérivées. Lui demander en plus de taper les marqueurs produirait des doublons.
 */
const CITE_RULE = `
- Place la référence de l'extrait, sous la forme [n], juste après chaque affirmation qu'il appuie.`;

export function systemFor(maxOrder: number | null, apiCitations: boolean): string {
  let s = SYSTEM;
  if (!apiCitations) s += CITE_RULE;
  if (maxOrder && maxOrder < BOOKS.length) s += "\n" + spoilerRule(maxOrder);
  return s;
}

function codexBlock(hits: CodexHit[]): string {
  const cards = hits.map((h) => {
    const e = h.entry;
    const rel = e.relations.slice(0, 6).map((r) => `${r.name} — ${r.nature}`).join(" · ");
    return [
      `### ${e.name} (${e.kind})`,
      e.aliases.length ? `Alias : ${e.aliases.join(", ")}` : "",
      e.gloss,
      e.description,
      e.arc ? `Évolution : ${e.arc}` : "",
      rel ? `Liens : ${rel}` : "",
      `Apparaît dans : ${e.books
        .map((o) => {
          const b = bookAt(o);
          return `${sagaOf(b.saga).short} ${b.tome === 0 ? "hors-série" : ROMAN[b.tome]}`;
        })
        .join(", ")}`,
    ].filter(Boolean).join("\n");
  });
  return `CODEX — fiches de synthèse (contexte, non citable comme texte du roman)\n\n${cards.join("\n\n")}`;
}

/**
 * Assemble le message envoyé à Claude.
 *
 * Chaque extrait est un bloc `document` avec citations activées : Claude renvoie
 * alors la portion exacte du passage sur laquelle il s'appuie, ce qui rend la
 * réponse vérifiable au lieu d'être simplement plausible.
 */
export function buildUserContent(
  question: string,
  hits: Hit[],
  codexHits: CodexHit[],
  useCitations: boolean,
): Anthropic.ContentBlockParam[] {
  const blocks: Anthropic.ContentBlockParam[] = [];

  if (codexHits.length) {
    blocks.push({ type: "text", text: codexBlock(codexHits) });
  }

  blocks.push({
    type: "text",
    text: hits.length
      ? `EXTRAITS — ${hits.length} passages retrouvés dans les romans, numérotés [1] à [${hits.length}].`
      : "EXTRAITS — aucun passage pertinent n'a été retrouvé pour cette question.",
  });

  hits.forEach((h, i) => {
    blocks.push({
      type: "document",
      source: { type: "text", media_type: "text/plain", data: h.chunk.text },
      title: `[${i + 1}] ${h.chunk.ref}`,
      context: `${sagaOf(h.chunk.saga).name}, tome ${ROMAN[h.chunk.tome]} — ${h.chunk.bookTitle}`,
      ...(useCitations ? { citations: { enabled: true } } : {}),
    });
  });

  blocks.push({ type: "text", text: `QUESTION\n${question}` });
  return blocks;
}

/**
 * Réinjecte un tour passé, sans ses documents ni ses appels de note.
 *
 * Les extraits ne sont pas renvoyés : l'historique resterait léger, mais surtout
 * les « [n] » d'une réponse précédente désignent SES extraits à elle. Au tour
 * suivant, la recherche en a retrouvé d'autres, et le même [3] pointe désormais
 * ailleurs. Laisser ces marqueurs inviterait le modèle à reprendre une
 * numérotation qui ne veut plus rien dire.
 */
export function historyText(text: string): Anthropic.ContentBlockParam[] {
  const stripped = text.replace(/\[\d{1,2}\]/g, "").replace(/[ \t]+([.,;:!?])/g, "$1").trim();
  return [{ type: "text", text: stripped || "(sans contenu)" }];
}
