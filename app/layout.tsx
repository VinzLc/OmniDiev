import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "L'Oracle d'Émeraude",
  description:
    "Tout savoir sur Les Chevaliers d'Émeraude d'Anne Robillard — réponses sourcées sur les douze tomes.",
};

/*
 * Sans cette déclaration, un téléphone compose la page sur une toile de 980
 * pixels puis la réduit : le site paraissait juste, en tout petit et coupé au
 * tiers. C'est la seule cause de l'essentiel de ce qui n'allait pas en mobile —
 * les feuilles de style, elles, savaient déjà se replier.
 *
 * `themeColor` teint ce que le navigateur peint au-delà du contenu — barre
 * d'adresse iOS, rebond de défilement. Sans elle, un liseré blanc borde un site
 * qui est noir partout ailleurs.
 */
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#060f0b",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
