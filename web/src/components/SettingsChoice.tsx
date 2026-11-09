import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import { Check, ChevronDown } from 'lucide-react';

// Keep the popup inside the dialog's DOM for focus containment, using the top
// layer so it cannot be clipped by the dialog's scrolling surface.
export function SettingsChoice<T extends string>({ label, value, options, onChange }: {
  label: string; value: T; options: readonly { value: T; label: string }[]; onChange: (value: T) => void;
}) {
  const [open, setOpen] = useState(false);
  const [keyboard, setKeyboard] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const id = useId();
  const supportsPopover = typeof HTMLElement !== 'undefined' && 'showPopover' in HTMLElement.prototype;
  const close = () => { setOpen(false); trigger.current?.focus({ preventScroll: true }); };

  useLayoutEffect(() => {
    if (!open || !menu.current || !trigger.current) return;
    const popup = menu.current;
    if (supportsPopover) popup.showPopover();
    const anchor = trigger.current.getBoundingClientRect();
    const bounds = popup.getBoundingClientRect();
    const margin = 8;
    const below = anchor.bottom + 4;
    const top = below + bounds.height <= window.innerHeight - margin ? below : anchor.top - bounds.height - 4;
    popup.style.left = `${Math.max(margin, Math.min(anchor.right - bounds.width, window.innerWidth - bounds.width - margin))}px`;
    popup.style.top = `${Math.max(margin, top)}px`;
    popup.querySelector<HTMLButtonElement>('[aria-checked=true]')?.focus({ preventScroll: true });
  }, [open, supportsPopover]);

  useEffect(() => {
    if (!open) return;
    const dismiss = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    const reposition = (event: Event) => {
      if (!menu.current?.contains(event.target as Node)) {
        setOpen(false);
        if (root.current?.contains(document.activeElement)) trigger.current?.focus({ preventScroll: true });
      }
    };
    document.addEventListener('pointerdown', dismiss);
    document.addEventListener('scroll', reposition, true);
    window.addEventListener('resize', reposition);
    return () => {
      document.removeEventListener('pointerdown', dismiss);
      document.removeEventListener('scroll', reposition, true);
      window.removeEventListener('resize', reposition);
    };
  }, [open]);

  return <div ref={root} className="settings-choice" data-keyboard={keyboard}
    onPointerDownCapture={() => setKeyboard(false)}
    onKeyDownCapture={() => setKeyboard(true)}
    onBlur={event => { if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false); }}>
    <button ref={trigger} type="button" className="settings-choice-trigger" aria-label={`${label}: ${options.find(option => option.value === value)?.label ?? ''}`}
      aria-haspopup="menu" aria-expanded={open} aria-controls={open ? id : undefined}
      onClick={event => { setKeyboard(event.detail === 0); setOpen(!open); }}
      onKeyDown={event => {
        if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); setOpen(true); }
      }}>
      <span>{options.find(option => option.value === value)?.label}</span><ChevronDown size={14} aria-hidden="true" />
    </button>
    {open && <div ref={menu} id={id} popover={supportsPopover ? 'manual' : undefined} className="category-assignment-menu settings-choice-menu" role="menu" aria-label={label}
      onKeyDown={event => {
        const nodes = [...event.currentTarget.querySelectorAll<HTMLButtonElement>('[role=menuitemradio]')];
        const index = nodes.indexOf(document.activeElement as HTMLButtonElement);
        if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(); }
        if (event.key === 'Tab') {
          event.preventDefault(); event.stopPropagation();
          const items = [...(root.current?.closest('[role=dialog]')?.querySelectorAll<HTMLElement>('button:not(:disabled):not([tabindex="-1"]), a[href], input:not(:disabled)') ?? [])];
          const origin = items.indexOf(trigger.current!);
          close();
          items[(origin + (event.shiftKey ? -1 : 1) + items.length) % items.length]?.focus();
        }
        if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
          event.preventDefault(); event.stopPropagation();
          nodes[event.key === 'Home' ? 0 : event.key === 'End' ? nodes.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + nodes.length) % nodes.length]?.focus();
        }
      }}>
      {options.map(option => <button key={option.value} type="button" role="menuitemradio" aria-checked={option.value === value} tabIndex={-1}
        onClick={() => { close(); onChange(option.value); }}>
        <span>{option.label}</span>{option.value === value && <Check size={15} aria-hidden="true" />}
      </button>)}
    </div>}
  </div>;
}
