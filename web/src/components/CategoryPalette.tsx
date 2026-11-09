import { useEffect, useRef, useState } from 'react';
import { Modal } from './Modal';
import { Check, ChevronDown } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import type { MessageCategoryColor } from '../api/client';
export const CATEGORY_PALETTE: { name: string; hex: string; color: MessageCategoryColor }[] = [
  ['Sky','#3b82f6','sky'],['Mint','#22c55e','mint'],['Amber','#f59e0b','amber'],['Coral','#ef4444','coral'],
  ['Violet','#a855f7','violet'],['Slate','#64748b','slate'],['Rose','#ec4899','rose'],['Ocean','#06b6d4','ocean'],
  ['Graphite','#676d78','slate'],['Denim','#4169a8','sky'],['Teal','#4a9a9d','ocean'],['Olive','#8da35e','mint'],
  ['Honey','#d9b24b','amber'],['Peach','#df8e73','coral'],['Berry','#af597b','rose'],['Lavender','#8276c2','violet'],
].map(([name, hex, color]) => ({ name, hex, color: color as MessageCategoryColor }));
// Legacy names and explicit shades must resolve through the same palette.
export function categoryHex(color: MessageCategoryColor, colorHex?: string | null): string {
  return (CATEGORY_PALETTE.find(preset => preset.hex === colorHex?.toLowerCase())
    ?? CATEGORY_PALETTE.find(preset => preset.color === color)
    ?? CATEGORY_PALETTE[5]).hex;
}
export function categoryStyle(colorHex: string | null | undefined, color: MessageCategoryColor): React.CSSProperties {
  return { '--category-accent': categoryHex(color, colorHex) } as React.CSSProperties;
}
export function CategoryPalette({ color, colorHex, onChange, expanded = false, showChevron = false }: {
  color: MessageCategoryColor; colorHex?: string | null;
  onChange: (color: MessageCategoryColor, hex: string) => void; expanded?: boolean; showChevron?: boolean;
}) {
  const { t } = useTranslation();
  const supportsPopover = typeof HTMLElement !== 'undefined' && typeof HTMLElement.prototype.showPopover === 'function';
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState({ left: 0, top: 0 });
  const trigger = useRef<HTMLButtonElement>(null);
  const popover = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open || !supportsPopover) return;
    popover.current?.showPopover();
    popover.current?.querySelector<HTMLButtonElement>('[aria-pressed=true]')?.focus({ preventScroll: true });
    const dismiss = (event: PointerEvent) => {
      if (!trigger.current?.contains(event.target as Node) && !popover.current?.contains(event.target as Node)) setOpen(false);
    };
    const close = () => setOpen(false);
    const escape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); setOpen(false); trigger.current?.focus(); }
    };
    document.addEventListener('pointerdown', dismiss);
    document.addEventListener('keydown', escape, true);
    window.addEventListener('resize', close);
    document.addEventListener('scroll', close, true);
    return () => {
      document.removeEventListener('pointerdown', dismiss);
      document.removeEventListener('keydown', escape, true);
      window.removeEventListener('resize', close);
      document.removeEventListener('scroll', close, true);
    };
  }, [open, supportsPopover]);
  const selectedHex = categoryHex(color, colorHex);
  const swatches = <div ref={popover} popover={expanded ? undefined : "manual"} className={expanded ? 'palette-grid' : 'palette-popover'} style={expanded ? undefined : position} role="group" aria-label={t('polish.color')}>
    {CATEGORY_PALETTE.map(item => <button key={item.hex} type="button" title={t(`polish.colors.${item.name}`)} aria-label={t(`polish.colors.${item.name}`)} aria-pressed={selectedHex === item.hex} style={{ background: item.hex }} onClick={() => {
      onChange(item.color, item.hex); setOpen(false); if (!expanded) trigger.current?.focus();
    }}>{selectedHex === item.hex && <Check size={18} strokeWidth={2.5} />}</button>)}
  </div>;
  if (expanded) return swatches;
  return <div className="category-palette">
    <button ref={trigger} type="button" className={`palette-trigger color-${color}${showChevron ? ' palette-trigger-dropdown' : ''}`} style={categoryStyle(colorHex, color)} aria-label={t('polish.color')} aria-expanded={open} onClick={() => {
      const bounds = trigger.current!.getBoundingClientRect();
      setPosition({ left: Math.max(12, Math.min(bounds.left, window.innerWidth - 208)), top: Math.max(12, Math.min(bounds.bottom + 4, window.innerHeight - 208)) });
      setOpen(value => !value);
    }}><span aria-hidden="true" />{showChevron && <ChevronDown size={12} aria-hidden="true" />}</button>
    {open && (supportsPopover ? swatches : <Modal title={t('polish.color')} message="" hideActions onCancel={() => setOpen(false)} onConfirm={() => setOpen(false)}>
      <CategoryPalette expanded color={color} colorHex={colorHex} onChange={(nextColor, hex) => { onChange(nextColor, hex); setOpen(false); }} />
    </Modal>)}
  </div>;
}
