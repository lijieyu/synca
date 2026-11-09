import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useTranslation } from 'react-i18next';

export const SIDEBAR_MIN = 200;
export const SIDEBAR_MAX = 360;
export const SIDEBAR_DEFAULT = 236;
const STORAGE_KEY = 'synca.sidebarWidth';
export function sidebarLimit(viewport: number) {
  return Math.max(SIDEBAR_MIN, Math.min(SIDEBAR_MAX, viewport - 480));
}
export function clampSidebar(value: number, viewport: number) {
  return Math.min(sidebarLimit(viewport), Math.max(SIDEBAR_MIN, Number.isFinite(value) ? value : SIDEBAR_DEFAULT));
}
export function SidebarFrame({ children }: { children: ReactNode }) {
  const { t } = useTranslation();
  const [preferred, setPreferred] = useState(() => {
    try { return clampSidebar(Number(localStorage.getItem(STORAGE_KEY) ?? SIDEBAR_DEFAULT), Infinity); } catch { return SIDEBAR_DEFAULT; }
  });
  const [viewport, setViewport] = useState(window.innerWidth);
  const [dragging, setDragging] = useState(false);
  const [hovered, setHovered] = useState(false);
  const recentMoves = useRef<boolean[]>([]);
  const drag = useRef<{ id: number; x: number; width: number; last: number; moved: boolean } | null>(null);
  const width = clampSidebar(preferred, viewport);
  const save = (value: number) => {
    const next = clampSidebar(value, window.innerWidth);
    setPreferred(next);
    try { localStorage.setItem(STORAGE_KEY, String(next)); } catch { /* Resizing still works when storage is unavailable. */ }
  };
  useEffect(() => {
    const resize = () => setViewport(window.innerWidth);
    window.addEventListener('resize', resize);
    return () => window.removeEventListener('resize', resize);
  }, []);
  useEffect(() => {
    if (!dragging) return;
    document.body.classList.add('sidebar-resizing');
    return () => document.body.classList.remove('sidebar-resizing');
  }, [dragging]);
  const finish = () => {
    const current = drag.current;
    if (!current) return;
    save(current.last);
    recentMoves.current = [...recentMoves.current.slice(-1), current.moved];
    drag.current = null; setDragging(false); setHovered(false);
  };
  return <aside className="calm-sidebar" style={{ '--sidebar-width': `${width}px` } as React.CSSProperties}>
    {children}
    <div className="sidebar-resizer" data-active={dragging || hovered} onPointerEnter={() => setHovered(true)} onPointerLeave={() => setHovered(false)} role="separator" aria-orientation="vertical" aria-label={t('navigation.resize_sidebar')}
      aria-valuemin={SIDEBAR_MIN} aria-valuemax={sidebarLimit(viewport)} aria-valuenow={Math.round(width)} tabIndex={0}
      onDoubleClick={() => { if (!recentMoves.current.some(Boolean)) save(SIDEBAR_DEFAULT); }}
      onKeyDown={event => {
        const next = event.key === 'ArrowLeft' ? width - 10 : event.key === 'ArrowRight' ? width + 10 : event.key === 'Home' ? SIDEBAR_MIN : event.key === 'End' ? sidebarLimit(viewport) : null;
        if (next !== null) { event.preventDefault(); save(next); }
      }}
      onPointerDown={event => {
        if (event.button !== 0 || !event.isPrimary) return;
        event.preventDefault(); event.currentTarget.blur();
        drag.current = { id: event.pointerId, x: event.clientX, width, last: width, moved: false };
        event.currentTarget.setPointerCapture(event.pointerId); setDragging(true);
      }}
      onPointerMove={event => {
        const start = drag.current;
        if (start?.id === event.pointerId) {
          start.moved ||= Math.abs(event.clientX - start.x) > 2;
          start.last = clampSidebar(start.width + event.clientX - start.x, window.innerWidth);
          setPreferred(start.last);
        }
      }}
      onPointerUp={event => {
        const start = drag.current;
        if (start?.id !== event.pointerId) return;
        start.last = clampSidebar(start.width + event.clientX - start.x, window.innerWidth); finish();
        if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
      }}
      onPointerCancel={finish}
      onLostPointerCapture={finish} />
  </aside>;
}
