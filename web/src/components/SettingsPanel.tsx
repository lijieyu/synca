import { SettingsSurface, type SettingsAction } from './SettingsSurface';
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import type { ReactNode } from 'react';
import { ArrowLeft, ChevronRight, Tags, Sparkles, MessageSquare, X, CircleUserRound, Info, Monitor, SlidersHorizontal } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { useAuth } from '../contexts/AuthContext';
import { ShellPanel, type AccountPage } from './ShellPanel';
import { AccountPlanLabel } from './PlanDialog';
import { Modal } from './Modal';
import {
  applyAppearance,
  readAppearancePreference,
  readLanguagePreference,
  resolveLanguage,
} from '../preferences';
import type { AppearancePreference, LanguagePreference } from '../preferences';
import './SettingsPanel.css';

const allSections = ['account', 'general', 'desktop', 'about'] as const;
type Section = (typeof allSections)[number];
const webSections = allSections.filter((key) => key !== 'desktop');
const icons = { general: SlidersHorizontal, desktop: Monitor, account: CircleUserRound, about: Info };
type Preferences = { badge: boolean; ask: boolean; directory: string };
export interface RecordMenuItem {
  id: string;
  label: string;
  enabled?: boolean;
  options?: {id: string; label: string; checked: boolean}[];
}
export interface RecordMenuOptions {
  x: number;
  y: number;
  link?: string;
  text?: string;
  selection?: string;
  items: (RecordMenuItem | null)[];
  attachment?: {url: string; name: string; kind: 'file' | 'image'; expiresAt?: string | null};
}
declare global {
  interface Window {
    syncaDesktop?: {
      platform: string;
      version: string;
      recordMenu?: (options: RecordMenuOptions) => Promise<string | null>;
      preferences: () => Promise<Preferences>;
      change: (key: 'ask' | 'badge', value: boolean) => Promise<Preferences>;
      directory: () => Promise<Preferences>;
      subscribe: (event: 'settings' | 'refresh' | 'sync', listener: () => void) => () => void;
      session: (token: string | null) => void;
      count: (count: number) => void;
    };
  }
}
export function openSettings(section: Section | SettingsAction = 'account') {
  window.dispatchEvent(new CustomEvent('synca-settings', { detail: section }));
}
export function SettingsFrame({ children }: { children: ReactNode }) {
  const { t, i18n } = useTranslation();
  const { token, email, logout } = useAuth();
  const [confirmLogout, setConfirmLogout] = useState(false);
  const [accountPage, setAccountPage] = useState<AccountPage>('overview');
  function showAccountPage(page: AccountPage) {
    setAccountPage(page);
    requestAnimationFrame(() => {
      const body = document.querySelector<HTMLElement>('.desk-detail-body:not([hidden])');
      body?.scrollTo(0, 0);
      document.querySelector<HTMLElement>('.settings-title h2')?.focus({preventScroll:true});
    });
  }
  const [desktopSection, setDesktopSection] = useState<Section | null>(null);
  const location = useLocation();
  const navigate = useNavigate();
  const desktop = window.syncaDesktop;
  const sections = desktop ? allSections : webSections;
  const [compact, setCompact] = useState(() => matchMedia('(width < 640px)').matches);
  const [mobileDetail, setMobileDetail] = useState(false);
  useEffect(() => {
    const media = matchMedia('(width < 640px)');
    const change = () => setCompact(media.matches);
    media.addEventListener('change', change);
    return () => media.removeEventListener('change', change);
  }, []);
  const mobileHome = compact && !mobileDetail;
  const requested = new URLSearchParams(location.search).get('settings');
  const section = desktop
    ? desktopSection
    : location.pathname === '/'
      ? (webSections.find((key) => key === requested) ?? null)
      : null;
  function setSection(next: Section | null) {
    setAccountPage('overview');
    if (desktop) {
      setDesktopSection(next);
      return;
    }
    if (!next && location.state?.fromSyncaWorkspace) {
      navigate(-1);
      return;
    }
    const params = new URLSearchParams(location.search);
    if (next) params.set('settings', next);
    else params.delete('settings');
    navigate(
      { pathname: location.pathname, search: params.toString(), hash: location.hash },
      {
        replace: section !== null,
        state: {
          ...location.state,
          fromSyncaWorkspace: next && (!section || location.state?.fromSyncaWorkspace),
        },
      },
    );
  }
  const [action, setAction] = useState<SettingsAction | null>(null);
  const [host, setHost] = useState<HTMLDivElement | null>(null);
  const pendingNavigation = useRef<(() => void) | null>(null);
  const directAction = useRef(false);
    const runAfterLeaving = (next: () => void) => {
    if (!action) { next(); return; }
    pendingNavigation.current = next;
    host?.querySelector<HTMLButtonElement>('[data-leave-section]')?.click();
  };
  function finishAction() {
    setAction(null);
    const next = pendingNavigation.current;
    pendingNavigation.current = null;
    next?.();
  }
  function openAction(key: SettingsAction) {
    if (key === action) { pendingNavigation.current = null; return; }
    runAfterLeaving(() => {
      setAction(key);
      window.dispatchEvent(new CustomEvent('synca-settings-action', {detail:key}));
    });
  }
  const [prefs, setPrefs] = useState<Preferences | null>(null);
  const [error, setError] = useState(false);
  const [appearance, setAppearance] = useState(readAppearancePreference);
  const [language, setLanguage] = useState(readLanguagePreference);
  const back = useRef<HTMLButtonElement>(null);
  const previous = useRef<HTMLElement | null>(null);
  const open = section !== null;

  useEffect(() => {
    desktop?.session(token);
  }, [token, desktop]);
  useEffect(() => {
    const show = (event: Event) => {
      if (document.querySelector('[aria-modal="true"]')) return;
      if (!open) previous.current = document.activeElement as HTMLElement;
      const target = (event as CustomEvent).detail;
      directAction.current = ['feedback','categories','ai'].includes(target);
      if (target === 'feedback' || target === 'categories' || target === 'ai') openAction(target);
      setMobileDetail(target === 'about');
      setSection(sections.includes(target) ? target : 'account');
    };
    window.addEventListener('synca-settings', show);
    const off = desktop?.subscribe('settings', () => openSettings());
    return () => {
      window.removeEventListener('synca-settings', show);
      off?.();
    };
  }, [open, desktop, location, section, compact, mobileDetail, action, host]);
  useLayoutEffect(() => {
    if (!open) return;
    back.current?.focus();
    let live = true;
    void desktop
      ?.preferences()
      .then((v) => {
        if (live) setPrefs(v);
      })
      .catch(() => {
        if (live) setError(true);
      });
    return () => {
      live = false;
    };
  }, [open, desktop]);
  useLayoutEffect(() => {
    if (!open || !action) return;
    host?.scrollTo(0, 0);
    if (compact) back.current?.focus({preventScroll:true});
    else document.querySelector<HTMLElement>('.settings-title h2')?.focus({preventScroll:true});
  }, [open, action, host, compact]);
  const wasOpen = useRef(false);
  useLayoutEffect(() => {
    if (!open && wasOpen.current) {
      const draft = document.querySelector<HTMLTextAreaElement>('.input-bar textarea');
      const target = draft?.value ? draft : previous.current;
      if (target?.isConnected && target !== document.body) target.focus({ preventScroll: true });
      else document.querySelector<HTMLElement>('.account-entry, textarea')?.focus({ preventScroll: true });
      previous.current = null;
    }
    wasOpen.current = open;
  }, [open]);
  function close() {
    if (action) {
      runAfterLeaving(() => { if (!compact || directAction.current) setSection(null); });
      return;
    }
    if (compact && mobileDetail) { setMobileDetail(false); setSection('account'); }
    else setSection(null);
  }
  function detail(next: Section) { setMobileDetail(true); setSection(next); }
  const actionKeys = {categories: 'message_list.manage_categories', ai: 'ai.connect', feedback: 'message_list.feedback'} as const;
  const actionIcons = {categories: Tags, ai: Sparkles, feedback: MessageSquare};
  function actions(keys = Object.keys(actionKeys) as SettingsAction[]) {
    return keys.map(key => {
      const Icon = actionIcons[key];
      return <button key={key} aria-current={action === key ? 'page' : undefined} onClick={() => openAction(key)}><Icon size={17} aria-hidden="true"/>{t(actionKeys[key])}{compact && <ChevronRight className="settings-disclosure" size={17} aria-hidden="true"/>}</button>;
    });
  }
  useEffect(() => {
    if (!open) return;
    const guard = (e: KeyboardEvent) => {
      if (e.isComposing || e.keyCode === 229 || document.querySelector('.modal-overlay')) return;
      if (e.key === 'Tab') {
        const controls = [...document.querySelectorAll<HTMLElement>('.desk-settings :is(button,select,input,textarea):not(:disabled), .desk-settings a[href], .desk-settings summary')].filter(el=>el.getClientRects().length && !el.closest('details:not([open]) > :not(summary)'));
        if (e.shiftKey && document.activeElement === controls[0] || !e.shiftKey && document.activeElement === controls.at(-1)) {
          e.preventDefault(); (e.shiftKey ? controls.at(-1) : controls[0])?.focus();
        }
      }
      if (e.key === 'Escape' && !(e.target instanceof HTMLSelectElement &&
          (!CSS.supports('selector(select:open)') || e.target.matches(':open')))) {
        e.preventDefault();
        close();
      }
      if (e.key === 'Escape' || ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'f'))
        e.stopImmediatePropagation();
    };
    window.addEventListener('keydown', guard, true);
    return () => window.removeEventListener('keydown', guard, true);
  }, [open, desktop, location, section, compact, mobileDetail, action, host]);
  async function update(operation: Promise<Preferences>, next?: Preferences) {
    const old = prefs;
    if (next) setPrefs(next);
    try {
      setPrefs(await operation);
      setError(false);
    } catch {
      setPrefs(old);
      setError(true);
    }
  }
  return (
    <>
      <div className="desk-workspace" inert={open}>
        <SettingsSurface.Provider value={{action,host,finish:finishAction,continueEditing:()=>{pendingNavigation.current=null;}}}>{children}</SettingsSurface.Provider>
      </div>
      {section && (
        <div className="settings-veil"><main className="desk-settings" role="dialog" aria-modal="true" aria-label={t('preferences.title')}>
          {!compact && <aside>
            <h1>{t('preferences.title')}</h1>
            <nav aria-label={t('preferences.title')} onKeyDown={event => {
              const buttons = Array.from(event.currentTarget.querySelectorAll('button'));
              const index = buttons.indexOf(event.target as HTMLButtonElement);
              if (index < 0 || event.metaKey || event.ctrlKey || event.altKey) return;
              const horizontal = window.matchMedia('(width < 640px)').matches;
              const destinations: Record<string, number> = {
                Home: 0,
                End: buttons.length - 1,
                [horizontal ? 'ArrowRight' : 'ArrowDown']: (index + 1) % buttons.length,
                [horizontal ? 'ArrowLeft' : 'ArrowUp']: (index + buttons.length - 1) % buttons.length,
              };
              const next = destinations[event.key];
              if (next === undefined) return;
              event.preventDefault();
              buttons[next].focus();
            }}>
              {sections.filter(key=>key!=='about').map((key) => {
                const Icon = icons[key];
                return (
                  <button
                    key={key}
                    aria-current={!action && section === key ? 'page' : undefined}
                    onClick={() => runAfterLeaving(() => setSection(key))}
                  >
                    <Icon size={17} />
                    <span className="settings-nav-label">{t(key === 'account' ? 'preferences.account_plan' : 'settings_page.' + key)}{key === 'account' && token && <small><AccountPlanLabel /></small>}</span>
                  </button>
                );
              })}
              {token && actions()}
              <button aria-current={!action && section==='about' ? 'page' : undefined} onClick={()=>runAfterLeaving(()=>setSection('about'))}><Info size={17}/>{t('settings_page.about')}</button>
            </nav>
          </aside>}
          <section className="desk-detail" key={section}>
            <header className={"settings-title"+(compact && (mobileDetail || action) ? " is-child" : "")}>
              {!compact && !action && section === 'account' && accountPage !== 'overview' && <button className="settings-back" onClick={() => showAccountPage('overview')} aria-label={t('settings_page.back')} title={t('settings_page.back')}><ArrowLeft size={19}/></button>}
              <h2 tabIndex={-1}>{t(action ? actionKeys[action] : mobileHome ? 'preferences.title' : !compact && section === 'account' ? ({overview:'preferences.account_plan',plan:'access.current_plan_title',methods:'email_auth.methods',manage:'review.page.manage_account'} as const)[accountPage] : 'settings_page.' + section)}</h2>
              <button ref={back} className="settings-close" onClick={close} aria-label={t(mobileHome && !action ? 'polish.done' : compact && (mobileDetail || action) ? 'settings_page.back' : 'navigation.close')}>{compact ? ((mobileDetail || action) ? <ArrowLeft/> : t('polish.done')) : <X size={20}/>}</button>
            </header>
            <div className="desk-detail-body" data-settings-action={action ?? undefined} ref={setHost} hidden={!action} />
            <div className="desk-detail-body" hidden={!!action}>
              {mobileHome && <button className="settings-identity" onClick={()=>detail('account')}><CircleUserRound size={34} aria-hidden="true"/><span>{email || t('navigation.account')}<small>{token ? <AccountPlanLabel /> : t('settings_page.signIn')}</small></span><ChevronRight className="settings-disclosure" size={17} aria-hidden="true"/></button>}
              {(section === 'general' || mobileHome) && (
                <><h3>{t('settings_group.preferences')}</h3><div className="settings-pref-group">
                  <label>
                    {t('preferences.appearance')}
                    <select
                      value={appearance}
                      onChange={(e) => {
                        const v = e.target.value as AppearancePreference;
                        applyAppearance(v);
                        setAppearance(v);
                      }}
                    >
                      {(['system', 'light', 'dark'] as const).map((v) => (
                        <option key={v} value={v}>
                          {t('preferences.' + v)}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    {t('preferences.language')}
                    <select
                      value={language}
                      onChange={(e) => {
                        const v = e.target.value as LanguagePreference;
                        localStorage.setItem('synca.language', v);
                        setLanguage(v);
                        void i18n.changeLanguage(resolveLanguage(v, navigator.languages));
                      }}
                    >
                      {(['system', 'zh-Hans', 'zh-Hant', 'en'] as const).map((v, i) => (
                        <option key={v} value={v}>
                          {[t('preferences.system'), '简体中文', '繁體中文', 'English'][i]}
                        </option>
                      ))}
                    </select>
                  </label></div>
                </>
              )}
              {section === 'desktop' && desktop && prefs && (
                <>
                  <h3>{t('review.page.notifications')}</h3>
                  <div className="settings-pref-group">
                  <label>
                    {t('settings_page.badge')}
                    <input
                      type="checkbox"
                      role="switch"
                      checked={prefs.badge}
                      onChange={(e) =>
                        void update(desktop.change('badge', e.target.checked), {
                          ...prefs,
                          badge: e.target.checked,
                        })
                      }
                    />
                  </label>
                  </div>
                  <h3>{t('review.page.downloads')}</h3>
                  <div className="settings-pref-group">
                  <label>
                    {t('settings_page.ask')}
                    <input
                      type="checkbox"
                      role="switch"
                      checked={prefs.ask}
                      onChange={(e) =>
                        void update(desktop.change('ask', e.target.checked), {
                          ...prefs,
                          ask: e.target.checked,
                        })
                      }
                    />
                  </label>
                  <div className="desk-row">
                    <div>
                      {t('settings_page.folder')}
                      <small>{prefs.directory || t('settings_page.downloads')}</small>
                    </div>
                    <button onClick={() => void update(desktop.directory())}>
                      {t('settings_page.choose')}
                    </button>
                  </div>
                  </div>
                  <p className="desktop-window-note">{t('review.page.window_note')}</p>
                </>
              )}
              {mobileHome && <>{token && <><h3>{t('settings_group.records')}</h3><div className="settings-links">{actions(['categories','ai'])}</div></>}<h3>{t('navigation.support')}</h3><div className="settings-links">{token && actions(['feedback'])}<button onClick={()=>detail('about')}><Info size={17} aria-hidden="true"/>{t('message_list.about')}<ChevronRight className="settings-disclosure" size={17} aria-hidden="true"/></button></div></>}
              {!mobileHome && (section === 'about' || section === 'account') &&
                (section === 'about' || token ? (
                  <ShellPanel
                    inline
                    kind={section}
                    accountPage={!compact ? accountPage : undefined}
                    onAccountPageChange={showAccountPage}
                    email={email}
                    onClose={close}
                    onLogout={() => setConfirmLogout(true)}
                  />
                ) : (
                  <p>{t('settings_page.signIn')}</p>
                ))}
              {confirmLogout && (
                <Modal
                  title={t('message_list.logout_confirm_title')}
                  message={t('message_list.logout_confirm_message')}
                  confirmText={t('message_list.logout')}
                  cancelText={t('common.cancel')}
                  destructive
                  onCancel={() => setConfirmLogout(false)}
                  onConfirm={() => {
                    setConfirmLogout(false);
                    logout();
                    close();
                  }}
                />
              )}
              {error && <p role="alert">{t('settings_page.error')}</p>}
            </div>
          </section>
        </main></div>
      )}
    </>
  );
}
