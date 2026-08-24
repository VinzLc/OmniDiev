/**
 * Détection de la source d'authentification disponible.
 *
 * Le SDK accepte trois voies, dans cet ordre de priorité :
 *   1. `ANTHROPIC_API_KEY`
 *   2. `ANTHROPIC_AUTH_TOKEN`
 *   3. un profil OAuth déposé par `ant auth login`
 *
 * Le code construit toujours un client nu (`new Anthropic()`), qui suit cette
 * chaîne tout seul. Ce module ne sert qu'à l'affichage et au diagnostic : exiger
 * `ANTHROPIC_API_KEY` avant d'appeler l'API rendrait le profil OAuth inutilisable
 * alors qu'il fonctionne parfaitement.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type CredentialSource = "api-key" | "auth-token" | "profile";

export type Credentials = {
  source: CredentialSource | null;
  /** Libellé affichable, sans jamais divulguer le secret. */
  label: string;
  /** Problème de configuration détecté malgré la présence d'un identifiant. */
  warning?: string;
};

function configDir(): string {
  if (process.env.ANTHROPIC_CONFIG_DIR) return process.env.ANTHROPIC_CONFIG_DIR;
  if (process.platform === "win32") {
    return path.join(process.env.APPDATA ?? os.homedir(), "Anthropic");
  }
  return path.join(os.homedir(), ".config", "anthropic");
}

/** Profils OAuth présents sur la machine, par nom. */
export function oauthProfiles(): string[] {
  const dir = path.join(configDir(), "credentials");
  try {
    return fs
      .readdirSync(dir)
      .filter((f) => f.endsWith(".json"))
      .map((f) => f.replace(/\.json$/, ""))
      .sort();
  } catch {
    return [];
  }
}

export function credentials(): Credentials {
  const key = process.env.ANTHROPIC_API_KEY;
  const token = process.env.ANTHROPIC_AUTH_TOKEN;

  // Les deux à la fois : le SDK les envoie tous les deux et l'API refuse.
  if (key && token) {
    return {
      source: "api-key",
      label: "clé API et jeton OAuth simultanés",
      warning:
        "ANTHROPIC_API_KEY et ANTHROPIC_AUTH_TOKEN sont tous deux définis — l'API rejettera les requêtes. N'en gardez qu'un.",
    };
  }

  if (key) {
    return { source: "api-key", label: `clé API (…${key.slice(-6)})` };
  }

  if (token) {
    return { source: "auth-token", label: "jeton OAuth (ANTHROPIC_AUTH_TOKEN)" };
  }

  const profiles = oauthProfiles();
  if (profiles.length) {
    const active = process.env.ANTHROPIC_PROFILE ?? "default";
    const found = profiles.includes(active);
    return {
      source: "profile",
      label: `profil OAuth « ${found ? active : profiles[0]} » (ant auth login)`,
      warning: found
        ? undefined
        : `ANTHROPIC_PROFILE désigne « ${active} », absent des profils installés (${profiles.join(", ")}).`,
    };
  }

  return { source: null, label: "aucun identifiant" };
}
