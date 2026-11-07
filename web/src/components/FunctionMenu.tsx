import { PersonIcon } from './PersonIcon';
import { useEffect, useRef, useState } from 'react';
import { ChevronDown, Tags, Sparkles, MessageSquareText, Info, Settings, LogOut } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import './FunctionMenu.css';

// Keep in the same order as MessageListView.settingsMenu on iOS/macOS.
export function FunctionMenu({ email, planLabel, usage, onAccount, onSettings, onCategories, onFeedback, onAbout, onLogout }: {
  email: string | null; planLabel: string; usage: { used: number; limit: number } | null;
  onAccount: () => void; onSettings: () => void; onCategories: () => void; onFeedback: () => void; onAbout: () => void; onLogout: () => void;
}) {
  const { t, i18n } = useTranslation();
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
    { title: t('message_list.manage_categories'), Icon: Tags, action: onCategories },
    { title: t('ai.connect'), Icon: Sparkles, href: `/ai?lng=${i18n.language}` },
    { title: t('message_list.feedback'), Icon: MessageSquareText, action: onFeedback },
    { title: t('message_list.about'), Icon: Info, action: onAbout },
    { title: t('message_list.logout'), Icon: LogOut, action: onLogout },
  ];
  return <div className="function-menu" ref={root} onBlur={e => { if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false); }}>
    <button ref={trigger} className="account-entry" aria-label={`${t('navigation.account')} · ${t('preferences.title')}`} title={`${t('navigation.account')} · ${t('preferences.title')}`} aria-haspopup="menu" aria-expanded={open}
      onClick={() => { keyboardOpen.current = false; setOpen(!open); }} onKeyDown={e => { if (e.key === 'ArrowDown') { e.preventDefault(); keyboardOpen.current = true; if (open) root.current?.querySelector<HTMLElement>('[role=menuitem]')?.focus(); else setOpen(true); } if (e.key === 'Escape') close(); }}><span className="identity-line"><span className="identity-avatar" aria-hidden="true"><PersonIcon size={22} /></span><span className="identity-copy"><strong>{email || t('navigation.account')}</strong><small>{planLabel}</small></span><ChevronDown size={15} /></span>
      {usage && <span className="daily-quota"><span>{t('preferences.daily_usage')}<span>{usage.used} / {usage.limit}</span></span><progress aria-label={t('preferences.daily_usage')} value={Math.min(usage.used, usage.limit)} max={Math.max(1, usage.limit)} /></span>}</button>
    {open && <div className="function-menu-panel" role="menu" aria-label={t('navigation.more')} onKeyDown={e => {
      const nodes = [...e.currentTarget.querySelectorAll<HTMLElement>('[role=menuitem]')];
      const index = nodes.indexOf(document.activeElement as HTMLElement);
      if (e.key === 'Escape') { e.preventDefault(); close(); }
      if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(e.key)) {
        e.preventDefault(); nodes[e.key === 'Home' ? 0 : e.key === 'End' ? nodes.length - 1 : (index + (e.key === 'ArrowDown' ? 1 : -1) + nodes.length) % nodes.length]?.focus();
      }
    }}><button role="menuitem" className="menu-account-header" onClick={() => { close(); onAccount(); }}><PersonIcon size={20} /><span>{t('preferences.account_plan')}<small>{email}</small></span></button><hr role="separator" />{items.map(({ title, Icon, action, href }, index) => <div key={title}>{index === 3 && <hr role="separator" />}{href
      ? <a key={title} role="menuitem" href={href} target="_blank" rel="noopener noreferrer" onClick={close}><Icon size={18} aria-hidden="true" />{title}</a>
      : <button key={title} role="menuitem" onClick={() => { close(); action?.(); }}><Icon size={18} aria-hidden="true" />{title}</button>}</div>)}</div>}
  </div>;
}
