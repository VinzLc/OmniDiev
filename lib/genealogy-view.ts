/**
 * Mise en forme des arbres généalogiques.
 *
 * Une seule implémentation, comme pour le Codex : routes locales et générateur
 * statique consomment la même chose.
 *
 * Chaque arbre est centré sur une personne et borné à deux générations de part
 * et d'autre. Les composantes connexes du graphe de parenté ne conviendraient
 * pas : de proche en proche, les alliances relient 173 personnages sur vingt-neuf
 * générations — illisible, et faux dès qu'une arête l'est.
 */
import fs from "node:fs";
import path from "node:path";
import { loadCodex } from "./codex.ts";
import { BOOKS } from "./books.ts";

export type Person = {
  name: string;
  parents: string[];
  children: string[];
  spouses: string[];
  siblings: string[];
};

type Graph = {
  builtAt: string;
  people: Record<string, Person>;
  trees: { id: string; name: string; size: number; books: number }[];
  kinds: Record<string, string>;
};

export type TreeCard = {
  id: string;
  name: string;
  gloss: string;
  kind: string;
  /** `ego`, `conjoint`, `fratrie` ou vide. */
  role: string;
};

export type Tree = {
  id: string;
  name: string;
  gloss: string;
  rows: { label: string; people: TreeCard[] }[];
  /** Filiations à tracer, restreintes aux personnes présentes. */
  links: { from: string; to: string; nature?: string }[];
  counts: { parents: number; children: number; spouses: number; siblings: number };
};

let graph: Graph | null | undefined;

function load(): Graph | null {
  if (graph !== undefined) return graph;
  const p = path.join(process.cwd(), "data", "index", "genealogy.json");
  if (!fs.existsSync(p)) return (graph = null);
  return (graph = JSON.parse(fs.readFileSync(p, "utf8")) as Graph);
}

export function genealogyIndex() {
  const g = load();
  const codex = loadCodex();
  if (!g || !codex) return { ready: false, trees: [] };

  const byId = new Map(codex.codex.entries.map((e) => [e.id, e]));
  return {
    ready: true,
    builtAt: g.builtAt,
    trees: g.trees.map((t) => {
      const p = g.people[t.id];
      return {
        id: t.id,
        name: t.name,
        size: t.size,
        gloss: byId.get(t.id)?.gloss ?? "",
        sagas: [...new Set(byId.get(t.id)?.books.map((o) => sagaOfOrder(o)) ?? [])].sort(),
        parents: p.parents.length,
        children: p.children.length,
        spouses: p.spouses.length,
        siblings: p.siblings.length,
      };
    }),
  };
}

/** Épopée d'un tome, par sa position absolue. */
function sagaOfOrder(order: number): number {
  return BOOKS.find((b) => b.order === order)?.saga ?? 0;
}

export function genealogyTree(id: string): Tree | null {
  const g = load();
  const codex = loadCodex();
  if (!g || !codex) return null;
  const ego = g.people[id];
  if (!ego) return null;

  const byId = new Map(codex.codex.entries.map((e) => [e.id, e]));
  const card = (pid: string, role = ""): TreeCard => ({
    id: pid,
    name: g.people[pid]?.name ?? byId.get(pid)?.name ?? pid,
    gloss: byId.get(pid)?.gloss ?? "",
    kind: byId.get(pid)?.kind ?? "personnage",
    role,
  });

  const uniq = (ids: string[]) => [...new Set(ids)];

  const grandparents = uniq(ego.parents.flatMap((p) => g.people[p]?.parents ?? []));
  const parents = uniq(ego.parents);
  const middle = uniq([id, ...ego.spouses, ...ego.siblings]);
  const children = uniq(ego.children);
  const grandchildren = uniq(children.flatMap((c) => g.people[c]?.children ?? []));

  const draft = [
    { label: "Grands-parents", people: grandparents.map((p) => card(p)) },
    { label: "Parents", people: parents.map((p) => card(p)) },
    {
      label: "Génération",
      people: middle.map((p) =>
        card(p, p === id ? "ego" : ego.spouses.includes(p) ? "conjoint" : "fratrie"),
      ),
    },
    { label: "Enfants", people: children.map((p) => card(p)) },
    { label: "Petits-enfants", people: grandchildren.map((p) => card(p)) },
  ];

  /*
   * Une personne ne paraît qu'une fois, dans la ligne qui la situe au plus près.
   *
   * Les lignées se recroisent : Kaliska est à la fois la sœur d'Onyx et sa
   * petite-fille. L'afficher deux fois embrouille la lecture, et fausse le
   * tracé — un trait cherche sa carte par identifiant et ne trouve que la
   * première.
   */
  const PRIORITY = ["Génération", "Parents", "Enfants", "Grands-parents", "Petits-enfants"];
  const placed = new Set<string>();
  for (const label of PRIORITY) {
    const row = draft.find((r) => r.label === label);
    if (!row) continue;
    row.people = row.people.filter((p) => {
      if (placed.has(p.id)) return false;
      placed.add(p.id);
      return true;
    });
  }
  const rows = draft.filter((r) => r.people.length > 0);

  // Ne tracer que les filiations dont les deux extrémités sont affichées.
  const present = new Set(rows.flatMap((r) => r.people.map((p) => p.id)));
  const links: Tree["links"] = [];
  for (const pid of present) {
    for (const parent of g.people[pid]?.parents ?? []) {
      if (present.has(parent)) {
        links.push({ from: parent, to: pid, nature: g.kinds[`${parent}>${pid}`] });
      }
    }
  }

  return {
    id,
    name: ego.name,
    gloss: byId.get(id)?.gloss ?? "",
    rows,
    links,
    counts: {
      parents: ego.parents.length,
      children: ego.children.length,
      spouses: ego.spouses.length,
      siblings: ego.siblings.length,
    },
  };
}

export function genealogyIds(): string[] {
  return load()?.trees.map((t) => t.id) ?? [];
}
