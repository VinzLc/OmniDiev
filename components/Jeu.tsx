"use client";

/**
 * Le jeu, dans la page.
 *
 * L'export web de Godot pèse une quarantaine de mégaoctets. On ne le charge
 * donc pas à l'ouverture de l'onglet : quelqu'un venu lire une fiche du Codex
 * n'a pas à télécharger un jeu qu'il n'a pas demandé. L'iframe n'est créée
 * qu'au clic, et le poids est annoncé avant.
 */

import { useCallback, useEffect, useRef, useState } from "react";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export default function Jeu() {
  const [lance, setLance] = useState(false);
  const [plein, setPlein] = useState(false);
  const cadre = useRef<HTMLDivElement>(null);

  /*
   * Deux plein-écrans plutôt qu'un.
   *
   * L'API Fullscreen ne s'applique qu'aux vidéos sur iOS : un iPhone aurait
   * gardé sa barre d'adresse par-dessus le jeu. On pose donc d'abord un
   * recouvrement en CSS, qui marche partout, et on demande le vrai plein écran
   * en plus — quand il existe, il retire aussi les barres du navigateur.
   */
  const ouvrir = useCallback(() => {
    setPlein(true);
    const el = cadre.current;
    if (el?.requestFullscreen) el.requestFullscreen().catch(() => {});
    // Le paysage n'est possible qu'en vrai plein écran, et jamais sur iOS.
    // L'échec est normal : la consigne affichée prend alors le relais.
    const o = screen.orientation as ScreenOrientation & {
      lock?: (s: string) => Promise<void>;
    };
    o?.lock?.("landscape").catch(() => {});
  }, []);

  const fermer = useCallback(() => {
    setPlein(false);
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  }, []);

  /*
   * Le bouton du navigateur et la touche Échap sortent du vrai plein écran
   * sans nous prévenir. Sans cette écoute, le recouvrement CSS resterait seul
   * en place et le jeu paraîtrait bloqué en grand.
   */
  useEffect(() => {
    const suivre = () => {
      if (!document.fullscreenElement) setPlein(false);
    };
    document.addEventListener("fullscreenchange", suivre);
    return () => document.removeEventListener("fullscreenchange", suivre);
  }, []);

  return (
    <div className={`jeu${plein ? " plein" : ""}`} ref={cadre}>
      {!lance ? (
        <div className="jeu-seuil">
          <h2>L&apos;Épopée de Wellan</h2>
          <p className="jeu-lede">
            Le premier tome, jouable — treize chapitres, de la fondation de l&apos;Ordre au
            débarquement de Zénor. Le jeu tourne dans cette page ; rien ne s&apos;installe.
          </p>
          <button className="jeu-lancer" onClick={() => setLance(true)}>
            Jouer
          </button>
          <p className="jeu-poids">
            Environ 40 Mo à télécharger · au clavier <b>ZQSD</b> ou aux commandes tactiles
          </p>
        </div>
      ) : (
        <>
          <iframe
            className="jeu-cadre"
            src={`${BASE}/jeu/index.html`}
            title="L'Épopée de Wellan"
            allow="fullscreen; autoplay; gamepad"
          />
          {/* Hors de l'iframe : à l'intérieur, le doigt appartient au jeu. */}
          <button
            className="jeu-plein"
            onClick={plein ? fermer : ouvrir}
            title={plein ? "Quitter le plein écran" : "Plein écran"}
          >
            {plein ? "✕" : "⤢"}
          </button>
          {plein && <p className="jeu-paysage">Tourne l&apos;appareil en paysage</p>}
        </>
      )}
    </div>
  );
}
