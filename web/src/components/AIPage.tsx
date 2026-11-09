import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { ArrowLeft, Copy, Check, Blocks, ChevronDown, ChevronUp } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuth } from '../contexts/AuthContext';
import { LoginView } from './LoginView';
import { PlanDialog } from './PlanDialog';
import { Modal } from './Modal';
import './AIPage.css';

type Scope = 'read' | 'create' | 'update' | 'delete' | 'attachments';
type Connection = { id: string; name: string; scopes: Scope[]; expires_at: string; revoked_at: string | null; last_used_at: string | null };
type Operation = { id: string; kind: string; status: string; created_at: string; connectionName?: string };
type Authorization = { aiEnabled: boolean; authorizationDays: number; autoRefresh: boolean; refreshIdleDays: number; clientName: string; scopes: Scope[]; redirectUri: string };

export function AIPage({ presentation = 'page' }: { presentation?: 'page' | 'dialog' } = {}) {
  const { token, isAuthenticated, accessStatus, refreshAccessStatus } = useAuth();
  const { t, i18n } = useTranslation();
  const zh = i18n.language.startsWith('zh');
  const labels: Record<Scope, string> = { read: t('ai_page.text_001'), create: t('ai_page.text_002'),
    update: t('ai_page.text_003'), delete: t('ai_page.text_004'), attachments: t('ai_page.text_005') };
  const actionLabels: Record<string, string> = {
    create_message: t('ai_page.text_006'), create_attachment: t('ai_page.text_007'), upload_attachment: t('ai_page.text_008'),
    update_messages: t('ai_page.text_009'), delete_messages: t('ai_page.text_010'),
    category_create: t('ai_page.text_011'), category_update: t('ai_page.text_012'), category_delete: t('ai_page.text_013'), category_reorder: t('ai_page.text_014'),
  };
  const statusLabels: Record<string, string> = { pending: t('ai_page.text_015'), completed: t('ai_page.text_016'), cancelled: t('ai_page.text_017'), expired: t('ai_page.text_018') };
  const params = new URLSearchParams(window.location.search);
  const authorize = presentation === 'page' ? params.get('authorize') : null;
  const embedded = presentation === 'dialog' || (window as Window & { __syncaEmbeddedAI?: boolean }).__syncaEmbeddedAI === true;
  const [guideVisible, setGuideVisible] = useState(false);
  const pageRef = useRef<HTMLElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const connectionScroll = useRef(0);
  const pendingTransition = useRef<{ height: number; scroll: number; focus: string | null } | null>(null);
  const animations = useRef<Animation[]>([]);
  const scroller = () => pageRef.current?.closest<HTMLElement>('.modal-scroll-body') ?? pageRef.current;
  const prepareTransition = (scroll = scroller()?.scrollTop ?? 0, focus: string | null = null) => {
    const height = contentRef.current?.getBoundingClientRect().height ?? 0;
    animations.current.forEach(animation => animation.cancel());
    pendingTransition.current = { height, scroll, focus };
  };
  const changeGuide = (visible: boolean) => {
    setPreviewVisible(false);
    if (visible) connectionScroll.current = scroller()?.scrollTop ?? 0;
    prepareTransition(visible ? 0 : connectionScroll.current, visible ? '.ai-guide-back' : '[data-guide-link]');
    setGuideVisible(visible);
  };
  const [loaded, setLoaded] = useState(false);
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [revokeTarget, setRevokeTarget] = useState<Connection | null>(null);
  const [connections, setConnections] = useState<Connection[]>([]);
  const [operations, setOperations] = useState<Operation[]>([]);
  const [operationsExpanded, setOperationsExpanded] = useState(false);
  const [authorization, setAuthorization] = useState<Authorization | null>(null);
  const [planVisible, setPlanVisible] = useState(false);
  const actionPending = useRef(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [copied, setCopied] = useState(false);
  const [previewVisible, setPreviewVisible] = useState(false);
  useLayoutEffect(() => {
    const pending = pendingTransition.current, content = contentRef.current;
    pendingTransition.current = null;
    if (!pending || !content) return;
    const restore = () => {
      scroller()?.scrollTo({ top: pending.scroll, behavior: 'instant' });
      if (pending.focus) content.querySelector<HTMLElement>(pending.focus)?.focus({ preventScroll: true });
    };
    const height = content.getBoundingClientRect().height;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches || !content.animate) { restore(); return; }
    // Animate the same surface; keep React state and the surrounding dialog alive.
    const size = content.animate([{ height: `${pending.height}px`, overflow: 'hidden' }, { height: `${height}px`, overflow: 'hidden' }], { duration: 200, easing: 'cubic-bezier(.2,.7,.2,1)' });
    const fade = content.animate([{ opacity: .35, transform: 'translateY(6px)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 180, easing: 'ease-out' });
    animations.current = [size, fade];
    void size.finished.then(restore, () => {});
    return () => { size.cancel(); fade.cancel(); };
  }, [guideVisible, operationsExpanded, previewVisible]);
  useEffect(() => {
    const update = (event: Event) => {
      const detail = (event as CustomEvent).detail;
      if (['zh-Hans', 'zh-Hant', 'en'].includes(detail?.language)) void i18n.changeLanguage(detail.language);
    };
    window.addEventListener('synca-native-preferences', update);
    return () => window.removeEventListener('synca-native-preferences', update);
  }, [i18n]);
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 2500);
    return () => window.clearTimeout(timer);
  }, [copied]);
  const [loginVisible, setLoginVisible] = useState(Boolean(authorize));
  const endpoint = `${window.location.origin}/mcp`;
  const connectionPrompt = t('ai_page.text_019', { value0: endpoint, value1: endpoint });
  const request = useCallback(async <T,>(path: string, method = 'GET', body?: unknown): Promise<T> => {
    const response = await fetch(`/api/ai/${path}`, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: body === undefined ? undefined : JSON.stringify(body), cache: 'no-store' });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
    return data;
  }, [token]);
  const refresh = useCallback(async () => {
    const [c, o] = await Promise.all([request<{ connections: Connection[] }>('connections'), request<{ operations: Operation[] }>('operations')]);
    setConnections(c.connections); setOperations(o.operations);
  }, [request]);
  useEffect(() => {
    if (presentation === 'dialog') return;
    document.title = `${t('ai.connect')} · Synca`;
    return () => { document.title = 'Synca'; };
  }, [t, presentation]);
  useEffect(() => {
    if (!token) return;
    let active = true;
    const load = async () => {
      const [c, o, a] = await Promise.all([
        request<{ connections: Connection[] }>('connections'), request<{ operations: Operation[] }>('operations'),
        authorize ? request<Authorization>(`authorization/${encodeURIComponent(authorize)}`) : null,
      ]);
      if (active) { setConnections(c.connections); setOperations(o.operations); setAuthorization(a); setLoaded(true); }
    };
    void load().catch(e => { if (active) setError(String(e.message)); });
    return () => { active = false; };
  }, [token, request, authorize, loadAttempt]);
  const act = async (fn: () => Promise<void>) => {
    if (actionPending.current) return;
    actionPending.current = true;
    setBusy(true); setError(''); setNotice('');
    try { await fn(); } catch (e) { setError(e instanceof Error ? e.message : String(e)); } finally { actionPending.current = false; setBusy(false); }
  };
  const copy = (value: string) => act(async () => { setCopied(false); await navigator.clipboard.writeText(value); setCopied(true); });
  const activeConnections = connections.filter(c => !c.revoked_at && new Date(c.expires_at).getTime() > Date.now());
  const showingTutorial = !authorize && (!isAuthenticated || (loaded && (!activeConnections.length || guideVisible)));
  return <><main ref={pageRef} className={`ai-page${authorize ? ' ai-authorization-page' : ''}${embedded ? ' ai-embedded' : ''}${presentation === 'dialog' ? ' ai-dialog' : ''}`} inert={planVisible || Boolean(revokeTarget)}><div ref={contentRef} className="ai-content">
    {!embedded && <nav className="ai-nav" aria-label={t('ai_page.text_020')}><Link className="ai-brand" to="/"><img src="/logo.png?v=a2" alt="" />Synca</Link></nav>}
    {guideVisible && activeConnections.length > 0 && <button className="ai-text-link ai-guide-back" onClick={() => changeGuide(false)}><ArrowLeft size={16} aria-hidden="true" />{t('ai_page.back_to_connections')}</button>}
    {showingTutorial && <section className="ai-tutorial">
      <div className="ai-tutorial-heading"><h1>{t('ai_refined.title')}</h1><span className="ai-pro-badge">{t('ai_refined.pro')}</span></div>
      <p className="ai-intro">{t('ai_refined.intro')}</p>
      <ol className="ai-steps">{[1, 2, 3].map(step => <li key={step}><div><strong>{t(`ai_refined.step${step}`)}</strong><p>{t(`ai_refined.detail${step}`)}</p></div></li>)}</ol>
      <button className="ai-primary ai-copy" disabled={busy} onClick={() => void copy(connectionPrompt)}>{copied ? <Check size={16} aria-hidden="true" /> : <Copy size={16} aria-hidden="true" />}<span aria-live="polite">{copied ? t('ai_page.text_028') : t('ai_refined.copy')}</span></button>
      <div className="ai-copy-foot"><p className="ai-tip">{t('ai_refined.tip')}</p><button className="ai-text-link" aria-expanded={previewVisible} aria-controls="ai-prompt-content" onClick={() => setPreviewVisible(value => !value)}>{t(previewVisible ? 'ai_refined.hide_prompt' : 'ai_refined.show_prompt')}{previewVisible ? <ChevronUp size={14} /> : <ChevronDown size={14} />}</button></div>
      {previewVisible && <div className="ai-prompt" id="ai-prompt-content">{connectionPrompt}</div>}
    </section>}
    {(authorize || isAuthenticated) && <div aria-live="polite" role="status" className="ai-notice">{notice}</div>}
    {error && <div role="alert" className="ai-error">{t('ai_page.text_036')}{error === 'ai_subscription_required' ? t('ai_page.text_037') : error}<button onClick={() => { if (presentation === 'dialog') { setError(''); setLoaded(false); setLoadAttempt(value => value + 1); } else window.location.reload(); }}>{t('ai_page.text_038')}</button></div>}
    {!showingTutorial && isAuthenticated && (authorization?.aiEnabled === false || (!authorize && accessStatus?.isUnlimited === false) || error === 'ai_subscription_required') && <section className="ai-card"><h2>{t('ai_page.text_039')}</h2><p>{t('ai_page.text_040')}</p><button className="ai-primary" onClick={() => setPlanVisible(true)}>{t('ai_page.text_041')}</button> <button disabled={busy} onClick={() => void act(async () => {
        await refreshAccessStatus();
        if (authorize) setAuthorization(await request<Authorization>(`authorization/${encodeURIComponent(authorize)}`));
        setNotice(t('ai_page.text_042'));
      })}>{t('ai_page.text_043')}</button></section>}
    {isAuthenticated && !loaded && !error && <div className="ai-initial-loading" role="status">{t('ai_page.text_044')}</div>}
    {!isAuthenticated && <section className={`ai-card ${!authorize ? 'ai-manage' : ''}`}><h2>{authorize ? t('ai_page.text_045') : t('ai_page.text_046')}</h2>
      <p>{t('ai_page.text_047')}</p>
      {!loginVisible ? <button className="ai-primary" onClick={() => setLoginVisible(true)}>{t('ai_page.text_048')}</button> : <div className="ai-login"><LoginView /></div>}
    </section>}
    {isAuthenticated && authorization && <section className="ai-card ai-consent"><h2>{t('ai_page.text_049')} · {authorization.clientName}</h2>
      <p>{t('ai_page.text_050')}</p>
      <p className="ai-wrap">{t('ai_page.text_051')}{authorization.redirectUri}</p>
      <ul>{authorization.scopes.map(s => <li key={s}>{labels[s]}</li>)}</ul>
      <p>{t('ai_page.text_052', { value0: authorization.authorizationDays })}</p>
      <p>{authorization.autoRefresh ? t('ai_page.text_053', { value0: authorization.refreshIdleDays }) : t('ai_page.text_054')}</p>
      <div className="ai-actions">{[true, false].map(approve => <button key={String(approve)} className={approve ? 'ai-primary' : ''} disabled={busy || (approve && !authorization.aiEnabled)} onClick={() => void act(async () => {
        const result = await request<{ redirectUrl: string }>(`authorization/${encodeURIComponent(authorize!)}`, 'POST', { approve });
        window.location.assign(result.redirectUrl);
      })}>{approve ? t('ai_page.text_055') : t('ai_page.text_056')}</button>)}</div>
    </section>}
    {isAuthenticated && !authorize && loaded && !showingTutorial && <>
      <section className="ai-card ai-connections"><div className="ai-section-heading"><h2>{t('ai_page.text_057')}</h2><button className="ai-text-link" data-guide-link onClick={() => changeGuide(true)}>{t('polish.tutorial')}</button></div>
        {!activeConnections.length && <p className="ai-muted">{t('ai_page.text_058')}</p>}
        {activeConnections.map(c => <article className="ai-connection" key={c.id}><div className="ai-app-mark" aria-hidden="true"><Blocks size={17} /></div><div className="ai-connection-meta"><h3>{c.name}</h3>
          <p className="ai-muted">{t('ai_page.text_059')}{new Date(c.expires_at).toLocaleDateString(i18n.language)}</p>
          <p className="ai-muted">{t('ai_page.text_060')}{c.last_used_at ? new Date(c.last_used_at).toLocaleString(i18n.language) : t('ai_page.text_061')}</p></div>
          <button className="ai-revoke" disabled={busy} onClick={() => setRevokeTarget(c)}>{t('ai_page.text_063')}</button></article>)}
      </section>
      <section className="ai-card ai-recent"><h2>{t('ai_page.text_064')}</h2>{!operations.length && <p className="ai-muted">{t('ai_page.text_065')}</p>}
        <ul className="ai-log" id="ai-operation-list">{(operationsExpanded ? operations : operations.slice(0, 3)).map(o => <li key={o.id}><span>{actionLabels[o.kind] ?? o.kind}<small>{o.connectionName ? `${o.connectionName} · ` : ''}{statusLabels[o.status] ?? o.status}</small></span><time dateTime={o.created_at}>{new Date(o.created_at).toLocaleString(i18n.language)}</time></li>)}</ul>
        {operationsExpanded && operations.length >= 50 && <p className="ai-muted ai-log-limit">{t('ai_page.operations_limit')}</p>}
        {operations.length > 3 && <div className="ai-section-actions"><button aria-expanded={operationsExpanded} aria-controls="ai-operation-list" onClick={() => { prepareTransition(); setOperationsExpanded(value => !value); }}>{t(operationsExpanded ? 'ai_page.operations_less' : 'ai_page.operations_more')}{operationsExpanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}</button></div>}
      </section>
    </>}
    {!embedded && <footer className="ai-muted">Synca · <Link to="/">{t('ai_page.text_066')}</Link> · <a href={zh ? '/zh-hans/privacy-policy' : '/en/privacy-policy'}>{t('ai_page.text_067')}</a></footer>}
    {planVisible && <PlanDialog onClose={() => setPlanVisible(false)} />}
  </div></main>{revokeTarget && <Modal title={t('polish.revokeTitle', { name: revokeTarget.name })} message={t('polish.revokeMessage')} destructive confirmText={t('ai_page.text_063')} cancelText={t('common.cancel')} confirmDisabled={busy} cancelDisabled={busy} closeDisabled={busy} onCancel={() => { if (!busy) setRevokeTarget(null); }} onConfirm={() => void act(async () => {
      await request(`connections/${encodeURIComponent(revokeTarget.id)}`, 'DELETE');
      setConnections(current => current.filter(c => c.id !== revokeTarget.id));
      setRevokeTarget(null); setNotice(t('ai_page.text_062')); await refresh();
    })}>{error && <p role="alert">{error}</p>}</Modal>}</>;
}
