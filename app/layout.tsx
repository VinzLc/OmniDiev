import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "L'Oracle d'Émeraude",
  description:
    "Tout savoir sur Les Chevaliers d'Émeraude d'Anne Robillard — réponses sourcées sur les douze tomes.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
