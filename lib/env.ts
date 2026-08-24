/**
 * Charge .env.local pour les scripts en ligne de commande.
 *
 * Next.js le fait pour l'application, mais pas `tsx scripts/…` : sans cela il
 * faudrait exporter la clé à la main avant chaque commande.
 * Les variables déjà présentes dans l'environnement gardent la priorité.
 */
import fs from "node:fs";
import path from "node:path";

export function loadEnv(root = process.cwd()) {
  for (const name of [".env.local", ".env"]) {
    const p = path.join(root, name);
    if (!fs.existsSync(p)) continue;

    for (const line of fs.readFileSync(p, "utf8").split("\n")) {
      const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
      if (!m) continue;

      const key = m[1];
      if (process.env[key] !== undefined) continue;

      let v = m[2].trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.slice(1, -1);
      }
      // Une valeur vide n'est pas neutre : `ANTHROPIC_API_KEY=` occuperait le
      // premier rang de la chaîne d'identifiants et authentifierait avec une
      // clé vide, masquant un profil OAuth parfaitement valide.
      if (!v) continue;
      process.env[key] = v;
    }
  }
}
