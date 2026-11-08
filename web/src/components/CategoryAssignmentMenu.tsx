import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Check, ChevronDown } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { categoryStyle } from './CategoryPalette';
import type { MessageCategory } from '../api/client';

export function CategoryAssignmentMenu({ categories, categoryId, disabled, onChange }: {
  categories: MessageCategory[]; categoryId: string | null; disabled: boolean; onChange: (id: string) => void;
}) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const menuId = useId();
  const menu = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState({ top: 0, left: 0 });
  useLayoutEffect(() => {
    if (!open || !trigger.current || !menu.current) return;
    const anchor = trigger.current.getBoundingClientRect();
    const bounds = menu.current.getBoundingClientRect();
    const top = anchor.top >= bounds.height + 8 ? anchor.top - bounds.height - 4 : anchor.bottom + 4;
    setPosition({ top: Math.max(8, Math.min(top, window.innerHeight - bounds.height - 8)), left: Math.max(8, Math.min(anchor.left, window.innerWidth - bounds.width - 8)) });
  }, [open]);
  const selected = categories.find(category => category.id === categoryId);
  const label = (category: MessageCategory) => category.isDefault ? t('message_category.default_badge') : category.name;
  const close = () => { setOpen(false); trigger.current?.focus(); };
  useEffect(() => {
    if (!open) return;
    (menu.current?.querySelector<HTMLElement>('[aria-checked=true]') ?? menu.current?.querySelector<HTMLElement>('[role=menuitemradio]'))?.focus({ preventScroll: true });
    const dismiss = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node) && !menu.current?.contains(event.target as Node)) setOpen(false); };
    const reposition = (event: Event) => { if (!menu.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener('scroll', reposition, true);
    window.addEventListener('resize', reposition);
    document.addEventListener('pointerdown', dismiss);
    return () => { document.removeEventListener('pointerdown', dismiss); document.removeEventListener('scroll', reposition, true); window.removeEventListener('resize', reposition); };
  }, [open]);
  return <div className="category-assignment" ref={root} onBlur={event => {
    if (!event.currentTarget.contains(event.relatedTarget) && !menu.current?.contains(event.relatedTarget)) setOpen(false);
  }}>
    <button ref={trigger} className="category-assignment-trigger" disabled={disabled} aria-label={`${t('storage.message_category')}: ${selected ? label(selected) : ''}`}
      aria-haspopup="menu" aria-expanded={open} aria-controls={open ? menuId : undefined} onClick={() => setOpen(!open)}
      onKeyDown={event => { if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); setOpen(true); } }}>
      {selected && <><span className={`category-color-dot color-${selected.color}`} style={categoryStyle(selected.colorHex)} aria-hidden="true" /><span>{label(selected)}</span></>}<ChevronDown size={10} aria-hidden="true" />
    </button>
    {open && createPortal(<div ref={menu} style={position} className="category-assignment-menu" id={menuId} role="menu" aria-label={t('storage.message_category')} onKeyDown={event => {
      const nodes = [...event.currentTarget.querySelectorAll<HTMLButtonElement>('[role=menuitemradio]')];
      const index = nodes.indexOf(document.activeElement as HTMLButtonElement);
      // Return the tab origin to the trigger before the browser advances focus.
      if (event.key === 'Tab') close();
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(); }
      if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
        event.preventDefault(); nodes[event.key === 'Home' ? 0 : event.key === 'End' ? nodes.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + nodes.length) % nodes.length]?.focus();
      }
    }}>
      {categories.map(category => <button key={category.id} role="menuitemradio" aria-checked={category.id === categoryId} tabIndex={-1} disabled={disabled}
        onClick={() => { close(); onChange(category.id); }}>
        <span className={`category-color-dot color-${category.color}`} style={categoryStyle(category.colorHex)} aria-hidden="true" /><span>{label(category)}</span>
        {category.id === categoryId && <Check size={15} aria-hidden="true" />}
      </button>)}
    </div>, document.body)}
  </div>;
}
