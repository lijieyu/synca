import { PersonIcon } from './PersonIcon';
import { useEffect, useRef, useState } from 'react';
import { ChevronDown, Info, LogOut, MessageSquareText, Settings } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import './FunctionMenu.css';

// Keep in the same order as MessageListView.settingsMenu on iOS/macOS.
export function FunctionMenu({ email, planLabel, usage, onAccount, onSettings, onFeedback, onAbout, onLogout }: {
  email: string | null; planLabel: string; usage: { used: number; limit: number } | null;
  onAccount: () => void; onSettings: () => void; onCategories: () => void; onAI: () => void; onFeedback: () => void; onAbout: () => void; onLogout: () => void;
}) {
  const { t } = useTranslation();
  const [compact, setCompact] = useState(() => matchMedia('(width < 640px)').matches);
  useEffect(() => {
    const media = matchMedia('(width < 640px)');
    const update = () => { setCompact(media.matches); setOpen(false); };
    media.addEventListener('change', update);
    return () => media.removeEventListener('change', update);
  }, []);
  const [pointerOpened, setPointerOpened] = useState(false);
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const keyboardOpen = useRef(false);
  const trigger = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!open) return;
    if (keyboardOpen.current) root.current?.querySelector<HTMLElement>('[role=menuitem]')?.focus();
    keyboardOpen.current = false;
    const dismiss = (e: PointerEvent) => { if (!root.current?.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('pointerdown', dismiss);
    return () => document.removeEventListener('pointerdown', dismiss);
  }, [open]);
  const close = () => { setOpen(false); trigger.current?.focus(); };
  const items = [
    { title: t('preferences.title'), Icon: Settings, action: onSettings },
    { title: t('message_list.feedback'), Icon: MessageSquareText, action: onFeedback },
  ];
  if (!compact) return <DesktopAccountMenu email={email} usage={usage} onSettings={onSettings} onFeedback={onFeedback} onAbout={onAbout} onLogout={onLogout} />;
  return <div className="function-menu" ref={root} onPointerDownCapture={() => { setPointerOpened(true); keyboardOpen.current = false; }} onKeyDownCapture={e => { if (['Tab', 'ArrowDown', 'ArrowUp', 'Home', 'End', 'Enter', ' '].includes(e.key)) setPointerOpened(false); }} onBlur={e => { if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false); }}>
    <button ref={trigger} className="account-entry" data-pointer-opened={pointerOpened} aria-label={`${t('navigation.account')} · ${t('preferences.title')}`} title={email || t('navigation.account')} aria-haspopup="menu" aria-expanded={open}
      onClick={e => { if (matchMedia('(width < 640px)').matches) { onSettings(); return; } keyboardOpen.current = e.detail === 0; setPointerOpened(e.detail !== 0); setOpen(!open); }} onKeyDown={e => { if (e.key === 'ArrowDown') { e.preventDefault(); keyboardOpen.current = true; if (open) root.current?.querySelector<HTMLElement>('[role=menuitem]')?.focus(); else setOpen(true); } if (e.key === 'Escape') close(); }}><span className="identity-line"><PersonIcon size={16} /><span className="identity-plan" title={email || undefined}>{email || t('navigation.account')}</span><ChevronDown size={15} /></span><span className="identity-email">{planLabel}</span>
      {usage && <span className="daily-quota"><span>{t('preferences.daily_usage')}<span>{usage.used} / {usage.limit}</span></span><progress aria-label={t('preferences.daily_usage')} value={Math.min(usage.used, usage.limit)} max={Math.max(1, usage.limit)} /></span>}</button>
    {open && <div className="function-menu-panel" role="menu" aria-label={t('navigation.more')} onKeyDown={e => {
      const nodes = [...e.currentTarget.querySelectorAll<HTMLElement>('[role=menuitem]')];
      const index = nodes.indexOf(document.activeElement as HTMLElement);
      if (e.key === 'Escape') { e.preventDefault(); close(); }
      if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(e.key)) {
        e.preventDefault(); nodes[e.key === 'Home' ? 0 : e.key === 'End' ? nodes.length - 1 : (index + (e.key === 'ArrowDown' ? 1 : -1) + nodes.length) % nodes.length]?.focus();
      }
    }}><button role="menuitem" className="menu-account-header" onClick={() => { close(); onAccount(); }}><PersonIcon size={18} /><span>{t('preferences.account_plan')}</span></button><hr role="separator" />{items.map(({ title, Icon, action }, index) => <div key={title}>{index === 3 && <hr role="separator" />}<button key={title} role="menuitem" onClick={() => { close(); action(); }}><Icon size={18} aria-hidden="true" />{title}</button></div>)}</div>}
  </div>;
}

function DesktopAccountMenu({ email, usage, onSettings, onFeedback, onAbout, onLogout }: {
  email: string | null; usage: { used: number; limit: number } | null;
  onSettings: () => void; onFeedback: () => void; onAbout: () => void; onLogout: () => void;
}) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const focusMenu = useRef(false);
  const close = () => { setOpen(false); trigger.current?.focus({ preventScroll: true }); };
  useEffect(() => {
    if (!open) return;
    if (focusMenu.current) root.current?.querySelector<HTMLElement>('[role="menuitem"]')?.focus();
    focusMenu.current = false;
    const dismiss = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener('pointerdown', dismiss);
    return () => document.removeEventListener('pointerdown', dismiss);
  }, [open]);
  const items = [
    { label: t('preferences.title'), Icon: Settings, action: onSettings },
    { label: t('message_list.feedback'), Icon: MessageSquareText, action: onFeedback },
    { label: t('polish.about_synca'), Icon: Info, action: onAbout },
  ];
  return <div className="function-menu desktop-account" ref={root}
    onBlur={event => { if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false); }}
    onKeyDown={event => { if (event.key === 'Escape' && open) { event.preventDefault(); event.stopPropagation(); close(); } }}>
    <div className="desktop-account-row">
      <div className="account-menu-anchor">
      <button ref={trigger} className="account-entry" title={email || t('navigation.account')} aria-label={t('navigation.account')} aria-haspopup="menu" aria-expanded={open}
        onClick={event => { focusMenu.current = event.detail === 0; setOpen(value => !value); }}
        onKeyDown={event => { if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); focusMenu.current = true; if (open) root.current?.querySelector<HTMLElement>('[role="menuitem"]')?.focus(); else setOpen(true); } }}>
        <span className="identity-avatar" aria-hidden="true"><PersonIcon size={20}/></span>
        <span className="identity-copy"><strong>{email || t('navigation.account')}</strong></span>
      </button>
    {open && <div className="function-menu-panel account-menu-panel" onKeyDown={event => {
      if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      const nodes = [...event.currentTarget.querySelectorAll<HTMLElement>('[role="menuitem"]')];
      const index = nodes.indexOf(document.activeElement as HTMLElement);
      nodes[event.key === 'Home' ? 0 : event.key === 'End' ? nodes.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + nodes.length) % nodes.length]?.focus();
    }}>
      <div className="account-menu-identity"><strong title={email || undefined}>{email || t('navigation.account')}</strong></div>
      <div role="menu" aria-label={t('navigation.account')}>
        <hr role="separator"/>
        {items.map(({label, Icon, action}) => <button key={label} role="menuitem" onClick={() => { close(); action(); }}><Icon size={16} aria-hidden="true"/><span>{label}</span></button>)}
        <hr role="separator"/>
        <button role="menuitem" onClick={() => { close(); onLogout(); }}><LogOut size={16} aria-hidden="true"/><span>{t('message_list.logout')}</span></button>
      </div>
    </div>}
      </div>
      <button className="settings-entry" onClick={onSettings} aria-label={t('preferences.title')} title={t('preferences.title')}><Settings size={18} aria-hidden="true"/></button>
    </div>
    {usage && <span className="daily-quota"><span>{t('preferences.daily_usage')}<span>{usage.used} / {usage.limit}</span></span><progress aria-label={t('preferences.daily_usage')} value={Math.min(usage.used, usage.limit)} max={Math.max(1, usage.limit)}/></span>}
  </div>;
}
