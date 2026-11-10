import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useTranslation } from 'react-i18next';
import './FunctionMenu.css';
import './CategoryContextMenu.css';

export interface CategoryMenuAnchor { id: string; x: number; y: number; trigger: HTMLButtonElement }

export function CategoryContextMenu({ anchor, name, protectedCategory, busy, canMoveUp, canMoveDown, onEdit, onMove, onDelete, onClose }: {
  anchor: CategoryMenuAnchor; name: string; protectedCategory: boolean; busy: boolean;
  canMoveUp: boolean; canMoveDown: boolean; onEdit: () => void; onMove: (direction: -1 | 1) => void;
  onDelete: () => void; onClose: () => void;
}) {
  const { t } = useTranslation();
  const menu = useRef<HTMLDivElement>(null);
  const closeRef = useRef(onClose);
  useLayoutEffect(() => { closeRef.current = onClose; });
  const [position, setPosition] = useState({ left: anchor.x, top: anchor.y });
  const close = (restore = true) => {
    if (restore && anchor.trigger.isConnected) anchor.trigger.focus({ preventScroll: true });
    closeRef.current();
  };
  useLayoutEffect(() => {
    const box = menu.current!.getBoundingClientRect();
    setPosition({ left: Math.max(8, Math.min(anchor.x, window.innerWidth - box.width - 8)), top: Math.max(8, Math.min(anchor.y, window.innerHeight - box.height - 8)) });
    (menu.current!.querySelector<HTMLButtonElement>('button:not(:disabled)') ?? menu.current)?.focus({ preventScroll: true });
  }, [anchor]);
  useEffect(() => {
    const dismiss = (event: PointerEvent) => { if (!menu.current?.contains(event.target as Node)) closeRef.current(); };
    const reposition = () => closeRef.current();
    document.addEventListener('pointerdown', dismiss);
    document.addEventListener('scroll', reposition, true);
    window.addEventListener('resize', reposition);
    return () => { document.removeEventListener('pointerdown', dismiss); document.removeEventListener('scroll', reposition, true); window.removeEventListener('resize', reposition); };
  }, []);
  const act = (action: () => void) => { close(); action(); };
  return createPortal(<div ref={menu} className="function-menu-panel category-context-menu" style={position} role="menu" aria-label={name} tabIndex={-1}
    onContextMenu={event => event.preventDefault()} onKeyDown={event => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(); }
      if (event.key === 'Tab') { close(); }
      if (['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) {
        event.preventDefault();
        const items = [...event.currentTarget.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];
        const current = items.indexOf(document.activeElement as HTMLButtonElement);
        items[event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : (current + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus();
      }
    }}>
    <button role="menuitem" tabIndex={-1} disabled={busy || protectedCategory} onClick={() => act(onEdit)}>{t('message_category.modify')}</button>
    <button role="menuitem" tabIndex={-1} disabled={busy || !canMoveUp} onClick={() => act(() => onMove(-1))}>{t('message_category.move_up')}</button>
    <button role="menuitem" tabIndex={-1} disabled={busy || !canMoveDown} onClick={() => act(() => onMove(1))}>{t('message_category.move_down')}</button>
    <div role="separator" />
    <button role="menuitem" tabIndex={-1} disabled={busy || protectedCategory} onClick={() => act(onDelete)}>{t('common.delete')}</button>
  </div>, document.body);
}
