import { useId, useLayoutEffect, useRef, useState } from 'react';
import { Check, ChevronDown } from 'lucide-react';
import './SettingsSelect.css';

type Option<T> = { value: T; label: string };
export function SettingsSelect<T extends string>({ label, value, options, onChange }: {
  label: string; value: T; options: Option<T>[]; onChange: (value: T) => void;
}) {
  const id = useId();
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const close = (restore = false) => { setOpen(false); if (restore) trigger.current?.focus(); };
  useLayoutEffect(() => {
    if (!open || !menu.current || !trigger.current) return;
    const panel = menu.current;
    panel.showPopover?.();
    const position = () => {
      const rect = trigger.current!.getBoundingClientRect();
      panel.style.minWidth = `${rect.width}px`;
      const height = panel.scrollHeight;
      const below = innerHeight - rect.bottom - 14;
      const above = rect.top - 14;
      const up = below < height && above > below;
      panel.style.maxHeight = `${Math.max(40, up ? above : below)}px`;
      panel.style.left = `${Math.max(8, Math.min(rect.right - panel.offsetWidth, innerWidth - panel.offsetWidth - 8))}px`;
      panel.style.top = `${up ? rect.top - panel.offsetHeight - 6 : rect.bottom + 6}px`;
    };
    position();
    panel.querySelector<HTMLElement>('[aria-selected="true"]')?.focus({ preventScroll: true });
    const outside = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node)) setOpen(false); };
    const resize = new ResizeObserver(position);
    resize.observe(trigger.current);
    window.addEventListener('resize', position);
    document.addEventListener('pointerdown', outside);
    document.addEventListener('scroll', position, true);
    return () => {
      panel.hidePopover?.(); resize.disconnect();
      window.removeEventListener('resize', position);
      document.removeEventListener('pointerdown', outside);
      document.removeEventListener('scroll', position, true);
    };
  }, [open]);
  return <div className="settings-select" ref={root} data-select-open={open || undefined}
    onKeyDown={event => {
      if (event.key === 'Escape' && open) { event.preventDefault(); event.stopPropagation(); close(true); }
      if (event.key === 'Tab' && open) {
        const dialog = root.current?.closest('[role="dialog"]');
        if (dialog) {
          event.preventDefault();
          const controls = [...dialog.querySelectorAll<HTMLElement>('button:not(:disabled),a[href],input:not(:disabled),select:not(:disabled),textarea:not(:disabled),[tabindex="0"]')]
            .filter(element => element.getClientRects().length && element.tabIndex >= 0 && !menu.current?.contains(element));
          const index = controls.indexOf(trigger.current!);
          close();
          controls[(index + (event.shiftKey ? -1 : 1) + controls.length) % controls.length]?.focus();
        } else close(true);
      }
      if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      if (!open) { setOpen(true); return; }
      const nodes = [...menu.current!.querySelectorAll<HTMLElement>('[role="option"]')];
      const index = nodes.indexOf(document.activeElement as HTMLElement);
      nodes[event.key === 'Home' ? 0 : event.key === 'End' ? nodes.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + nodes.length) % nodes.length]?.focus();
    }}>
    <button ref={trigger} type="button" className="settings-select-trigger" role="combobox" aria-label={label}
      aria-expanded={open} aria-haspopup="listbox" aria-controls={id} onClick={() => setOpen(!open)}>
      <span>{options.find(option => option.value === value)?.label}</span><ChevronDown size={15} aria-hidden="true"/>
    </button>
    {open && <div ref={menu} id={id} role="listbox" aria-label={label} popover="manual" className="settings-select-options">
      {options.map(option => <button type="button" key={option.value} role="option" tabIndex={-1} aria-selected={value === option.value}
        onClick={() => { onChange(option.value); close(true); }}><span>{option.label}</span><Check size={15} aria-hidden="true" style={{visibility:value === option.value ? 'visible':'hidden'}}/></button>)}
    </div>}
  </div>;
}
