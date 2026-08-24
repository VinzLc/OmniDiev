/**
 * Deux modes de construction.
 *
 * Par défaut : l'application complète, avec ses routes serveur — c'est ce qui
 * tourne en local, la clé API restant côté serveur.
 *
 * `PAGES=1` : export statique du seul Codex, pour GitHub Pages. L'Oracle en est
 * absent par nécessité et par choix — un site statique ne peut pas détenir de
 * secret, et le faire fonctionner supposerait de publier l'index de recherche,
 * c'est-à-dire le texte intégral des romans.
 */
const pages = process.env.PAGES === "1";
const repo = process.env.PAGES_BASE ?? "/OmniDiev";

/** @type {import('next').NextConfig} */
const nextConfig = {
  serverExternalPackages: ["@huggingface/transformers", "onnxruntime-node"],
  devIndicators: false,
  ...(pages
    ? {
        output: "export",
        basePath: repo,
        trailingSlash: true,
        images: { unoptimized: true },
        env: { NEXT_PUBLIC_BASE_PATH: repo, NEXT_PUBLIC_STATIC: "1" },
      }
    : {}),
};
export default nextConfig;
