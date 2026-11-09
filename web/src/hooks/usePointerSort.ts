import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';

export function moveItem<T>(items: readonly T[], from: number, to: number): T[] {
  const next = [...items];
  if (from < 0 || to < 0 || from >= next.length || to >= next.length) return next;
  next.splice(to, 0, next.splice(from, 1)[0]);
  return next;
}

/** Transform the existing DOM rows: no drag image, duplicated controls, or reordered focus. */
export function usePointerSort({ disabled, onStart, onEnd, onCommit }: {
  disabled: boolean;
  onStart: () => void;
  onEnd: () => void;
  onCommit: (source: string, target: string) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const cleanup = useRef<(() => void) | null>(null);
  const callbacks = useRef({ onStart, onEnd, onCommit });
  callbacks.current = { onStart, onEnd, onCommit };
  const [active, setActive] = useState(false);
  useEffect(() => () => cleanup.current?.(), []);
  useEffect(() => { if (disabled) cleanup.current?.(); }, [disabled]);

  const begin = (event: ReactPointerEvent<HTMLElement>, id: string, allowTouch = false) => {
    if (disabled || event.button !== 0 || !event.isPrimary || (event.pointerType === 'touch' && !allowTouch)) return;
    const container = containerRef.current;
    if (!container || cleanup.current) return;
    const rows = Array.from(container.querySelectorAll<HTMLElement>('[data-sort-id]'));
    const from = rows.findIndex(row => row.dataset.sortId === id);
    if (from < 0 || rows.length < 2) return;
    const rects = rows.map(row => row.getBoundingClientRect());
    const layout = getComputedStyle(container);
    const horizontal = layout.display.includes('flex') && layout.flexDirection === 'row';
    const start = horizontal ? event.clientX : event.clientY;
    const pointerId = event.pointerId;
    const handle = event.currentTarget;
    const picked = rows[from];
    const scrollParent = container.parentElement!;
    const initialScroll = horizontal ? scrollParent.scrollLeft : scrollParent.scrollTop;
    let dragging = false;
    let to = from;
    let lastX = event.clientX;
    let lastY = event.clientY;
    let frame = 0;
    const size = (rect: DOMRect) => horizontal ? rect.width : rect.height;
    const leading = (rect: DOMRect) => horizontal ? rect.left : rect.top;
    const gap = rects.length > 1 ? leading(rects[1]) - leading(rects[0]) - size(rects[0]) : 0;
    const inside = () => {
      const bounds = scrollParent.getBoundingClientRect();
      return lastX >= bounds.left - 16 && lastX <= bounds.right + 16 && lastY >= bounds.top - 16 && lastY <= bounds.bottom + 16;
    };
    const paint = () => {
      const scrollDelta = (horizontal ? scrollParent.scrollLeft : scrollParent.scrollTop) - initialScroll;
      const delta = (horizontal ? lastX : lastY) - start + scrollDelta;
      const center = leading(rects[from]) + size(rects[from]) / 2 + delta;
      to = from;
      rects.forEach((rect, index) => {
        if (index < from && center <= leading(rect) + size(rect) / 2) to = Math.min(to, index);
        if (index > from && center >= leading(rect) + size(rect) / 2) to = Math.max(to, index);
      });
      rows.forEach((row, index) => {
        const offset = index === from ? delta : from < to && index > from && index <= to ? -size(rects[from]) - gap : to < from && index >= to && index < from ? size(rects[from]) + gap : 0;
        row.style.transform = horizontal ? `translate3d(${offset}px,0,0)` : `translate3d(0,${offset}px,0)`;
      });
    };
    const autoScroll = () => {
      if (!dragging) return;
      const bounds = scrollParent.getBoundingClientRect();
      const position = horizontal ? lastX : lastY;
      const edgeStart = horizontal ? bounds.left : bounds.top;
      const edgeEnd = horizontal ? bounds.right : bounds.bottom;
      if (inside()) {
        const speed = position < edgeStart + 28 ? -6 : position > edgeEnd - 28 ? 6 : 0;
        if (horizontal) scrollParent.scrollLeft += speed; else scrollParent.scrollTop += speed;
        paint();
      }
      frame = requestAnimationFrame(autoScroll);
    };
    const stop = (commit = false) => {
      cancelAnimationFrame(frame);
      handle.removeEventListener('lostpointercapture', cancel);
      if (handle.hasPointerCapture(pointerId)) handle.releasePointerCapture(pointerId);
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', up);
      document.removeEventListener('pointercancel', cancel);
      document.removeEventListener('keydown', key);
      window.removeEventListener('blur', cancel);
      window.removeEventListener('resize', cancel);
      cleanup.current = null;
      rows.forEach(row => { row.style.transform = ''; row.classList.remove('sortable-row', 'sortable-picked'); });
      if (!dragging) return;
      setActive(false);
      // A pointer drag must never turn into selection or a double-click editor.
      const suppressClick = (e: MouseEvent) => { e.preventDefault(); e.stopImmediatePropagation(); };
      document.addEventListener('click', suppressClick, true);
      window.setTimeout(() => document.removeEventListener('click', suppressClick, true), 0);
      callbacks.current.onEnd();
      if (commit && inside() && to !== from) callbacks.current.onCommit(id, rows[to].dataset.sortId!);
    };
    const move = (e: PointerEvent) => {
      if (e.pointerId !== pointerId) return;
      if (e.pointerType === 'mouse' && e.buttons === 0) { stop(); return; }
      lastX = e.clientX; lastY = e.clientY;
      if (!dragging && Math.abs((horizontal ? lastX : lastY) - start) < 6) return;
      e.preventDefault();
      if (!dragging) {
        handle.setPointerCapture(pointerId);
        handle.addEventListener('lostpointercapture', cancel);
        dragging = true; setActive(true); callbacks.current.onStart();
        rows.forEach(row => row.classList.add('sortable-row'));
        picked.classList.add('sortable-picked');
        frame = requestAnimationFrame(autoScroll);
      }
      paint();
    };
    const up = (e: PointerEvent) => { if (e.pointerId === pointerId) { lastX = e.clientX; lastY = e.clientY; stop(true); } };
    const cancel = () => stop();
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); stop(); } };
    cleanup.current = cancel;
    document.addEventListener('pointermove', move, { passive: false });
    document.addEventListener('pointerup', up);
    document.addEventListener('pointercancel', cancel);
    document.addEventListener('keydown', key);
    window.addEventListener('blur', cancel);
    window.addEventListener('resize', cancel);
  };
  return { containerRef, begin, active };
}
