import { useEffect, useRef, useState } from 'react';
import { Check } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import type { MessageCategoryColor } from '../api/client';
export const CATEGORY_PALETTE: { name: string; hex: string; color: MessageCategoryColor }[] = [
  ['Sky','#3b82f6','sky'],['Mint','#22c55e','mint'],['Amber','#f59e0b','amber'],['Coral','#ef4444','coral'],
  ['Violet','#a855f7','violet'],['Slate','#64748b','slate'],['Rose','#ec4899','rose'],['Ocean','#06b6d4','ocean'],
  ['Graphite','#676d78','slate'],['Denim','#4169a8','sky'],['Teal','#4a9a9d','ocean'],['Olive','#8da35e','mint'],
  ['Honey','#d9b24b','amber'],['Peach','#df8e73','coral'],['Berry','#af597b','rose'],['Lavender','#8276c2','violet'],
].map(([name, hex, color]) => ({ name, hex, color: color as MessageCategoryColor }));
export function categoryStyle(colorHex?: string | null): React.CSSProperties | undefined {
  return CATEGORY_PALETTE.some(p => p.hex === colorHex) ? { '--category-accent': colorHex } as React.CSSProperties : undefined;
}
export function CategoryPalette({ color, colorHex, onChange }: {color: MessageCategoryColor; colorHex?: string | null; onChange: (color: MessageCategoryColor, hex: string) => void}) {
 const { t } = useTranslation(); const [open,setOpen] = useState(false); const root = useRef<HTMLDivElement>(null); const trigger = useRef<HTMLButtonElement>(null);
 useEffect(() => { if (!open) return; const dismiss = (e: PointerEvent) => { if (!root.current?.contains(e.target as Node)) setOpen(false); }; document.addEventListener('pointerdown',dismiss); return () => document.removeEventListener('pointerdown',dismiss); }, [open]);
 return <div className="category-palette" ref={root} onKeyDown={e => { if(e.key === 'Escape') { e.stopPropagation(); setOpen(false); trigger.current?.focus(); } }}>
 <button ref={trigger} type="button" className={`palette-trigger color-${color}`} style={categoryStyle(colorHex)} aria-label={t('polish.color')} aria-expanded={open} onClick={() => setOpen(!open)}><span /></button>
 {open && <div className="palette-popover" role="group" aria-label={t('polish.color')}>{CATEGORY_PALETTE.map(p => <button key={p.hex} type="button" title={t(`polish.colors.${p.name}`)} aria-label={t(`polish.colors.${p.name}`)} aria-pressed={colorHex ? colorHex === p.hex : color === p.color && CATEGORY_PALETTE.find(c => c.color === color)?.hex === p.hex} style={{background:p.hex}} onClick={() => {onChange(p.color,p.hex);setOpen(false);trigger.current?.focus();}}>{(colorHex ? colorHex === p.hex : CATEGORY_PALETTE.find(c => c.color === color)?.hex === p.hex) && <Check size={18} />}</button>)}</div>}
 </div>;
}
