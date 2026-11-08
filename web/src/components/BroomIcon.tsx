/** A wide cleaning brush, distinct from the trash action used to delete one record. */
export function BroomIcon({ size = 18 }: { size?: number }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M10 10V4a2 2 0 0 1 4 0v6M4 10h16v4H4zM5 14l-1 6h16l-1-6M8 16v4m4-4v4m4-4v4" />
  </svg>;
}
