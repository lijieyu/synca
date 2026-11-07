/** Neutral account identity; intentionally has no editable-avatar affordance. */
export function PersonIcon({ size = 20 }: { size?: number }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false">
    <circle cx="12" cy="7" r="4" />
    <path d="M4 20a8 8 0 0 1 16 0v1H4z" />
  </svg>;
}
