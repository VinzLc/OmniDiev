/** Losange d'émeraude facetté — emblème de l'Ordre. */
export function Sigil({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 48 48" fill="none" aria-hidden="true">
      <path d="M24 2 44 20 24 46 4 20 24 2Z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
      <path d="M4 20h40M24 2 14 20l10 26M24 2l10 18-10 26" stroke="currentColor" strokeWidth="1.1" strokeLinejoin="round" opacity="0.55" />
      <path d="M24 2 44 20 24 46 4 20 24 2Z" fill="currentColor" opacity="0.09" />
    </svg>
  );
}
