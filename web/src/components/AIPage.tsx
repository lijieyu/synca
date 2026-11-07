import { useCallback, useEffect, useState } from 'react';
import { ArrowUpRight, Copy, Check, MessageSquare } from 'lucide-react';
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

export function AIPage() {
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
  const authorize = params.get('authorize');
  const [connections, setConnections] = useState<Connection[]>([]);
  const [operations, setOperations] = useState<Operation[]>([]);
  const [authorization, setAuthorization] = useState<Authorization | null>(null);
  const [planVisible, setPlanVisible] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [copied, setCopied] = useState(false);
  const [previewVisible, setPreviewVisible] = useState(false);
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
    document.title = `${t('ai.connect')} · Synca`;
    return () => { document.title = 'Synca'; };
  }, [t]);
  useEffect(() => {
    if (!token) return;
    let active = true;
    setLoading(true);
    const load = async () => {
      const [c, o, a] = await Promise.all([
        request<{ connections: Connection[] }>('connections'), request<{ operations: Operation[] }>('operations'),
        authorize ? request<Authorization>(`authorization/${encodeURIComponent(authorize)}`) : null,
      ]);
      if (active) { setConnections(c.connections); setOperations(o.operations); setAuthorization(a); }
    };
    void load().catch(e => { if (active) setError(String(e.message)); }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [token, request, authorize]);
  const act = async (fn: () => Promise<void>) => {
    if (busy) return;
    setBusy(true); setError(''); setNotice('');
    try { await fn(); } catch (e) { setError(e instanceof Error ? e.message : String(e)); } finally { setBusy(false); }
  };
  const copy = (value: string) => act(async () => { setCopied(false); await navigator.clipboard.writeText(value); setCopied(true); });
  const activeConnections = connections.filter(c => !c.revoked_at && new Date(c.expires_at).getTime() > Date.now());
  return <main className={`ai-page${authorize ? ' ai-authorization-page' : ''}${previewVisible ? ' ai-preview-open' : ''}`} inert={previewVisible || planVisible}><div className="ai-content">
    <nav className="ai-nav" aria-label={t('ai_page.text_020')}><Link className="ai-brand" to="/"><img src="/logo.png" alt="" />Synca</Link></nav>
    {!authorize && <><div className="ai-intro-grid"><header className="ai-hero">
      <h1>{t('ai_page.text_021')}</h1>
      <p>{t('ai_page.text_022')}</p>
    </header>
    <section className="ai-card ai-connect" id="connect"><h2>{t('ai_page.text_023')}</h2>
      <p className="ai-muted">{t('ai_page.text_024')}</p>
      <ol><li>{t('ai_page.text_025')}</li>
        <li>{t('ai_page.text_026')}</li>
        <li>{t('ai_page.text_027')}</li></ol>
      <button className="ai-primary" disabled={busy} onClick={() => void copy(connectionPrompt)}>{copied ? <Check size={18} aria-hidden="true" /> : <Copy size={18} aria-hidden="true" />}<span aria-live="polite">{copied ? t('ai_page.text_028') : t('ai_page.text_029')}</span></button>
      <p className="ai-muted">{t('ai_page.text_030')}</p>
      <button className="ai-preview-trigger" aria-haspopup="dialog" onClick={() => setPreviewVisible(true)}>{t('ai_page.text_031')}<ArrowUpRight size={15} aria-hidden="true" /></button>
    </section></div>
    <section className="ai-examples" aria-label={t('ai_page.text_032')}>
      {[t('ai_page.text_033'), t('ai_page.text_034'), t('ai_page.text_035')].map(v => <p key={v}><MessageSquare size={18} aria-hidden="true" />{v}</p>)}
    </section>
    </>}
    {(authorize || isAuthenticated) && <div aria-live="polite" role="status" className="ai-notice">{notice}</div>}
    {error && <div role="alert" className="ai-error">{t('ai_page.text_036')}{error === 'ai_subscription_required' ? t('ai_page.text_037') : error}<button onClick={() => window.location.reload()}>{t('ai_page.text_038')}</button></div>}
    {isAuthenticated && (authorization?.aiEnabled === false || (!authorize && accessStatus?.isUnlimited === false) || error === 'ai_subscription_required') && <section className="ai-card"><h2>{t('ai_page.text_039')}</h2><p>{t('ai_page.text_040')}</p><button className="ai-primary" onClick={() => setPlanVisible(true)}>{t('ai_page.text_041')}</button> <button disabled={busy} onClick={() => void act(async () => {
        await refreshAccessStatus();
        if (authorize) setAuthorization(await request<Authorization>(`authorization/${encodeURIComponent(authorize)}`));
        setNotice(t('ai_page.text_042'));
      })}>{t('ai_page.text_043')}</button></section>}
    {loading && <p role="status">{t('ai_page.text_044')}</p>}
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
    {isAuthenticated && !authorize && <>
      <section className="ai-card"><h2>{t('ai_page.text_057')}</h2>
        {!activeConnections.length && <p className="ai-muted">{t('ai_page.text_058')}</p>}
        {activeConnections.map(c => <article className="ai-connection" key={c.id}><div><h3>{c.name}</h3><p>{c.scopes.map(s => labels[s]).join(' · ')}</p>
          <p className="ai-muted">{t('ai_page.text_059')}{new Date(c.expires_at).toLocaleDateString(i18n.language)} · {t('ai_page.text_060')}{c.last_used_at ? new Date(c.last_used_at).toLocaleString(i18n.language) : t('ai_page.text_061')}</p></div>
          <button disabled={busy} onClick={() => void act(async () => { await request(`connections/${c.id}`, 'DELETE'); await refresh(); setNotice(t('ai_page.text_062')); })}>{t('ai_page.text_063')}</button></article>)}
      </section>
      <section className="ai-card"><h2>{t('ai_page.text_064')}</h2>{!operations.length && <p className="ai-muted">{t('ai_page.text_065')}</p>}
        <ul className="ai-log">{operations.map(o => <li key={o.id}><span>{actionLabels[o.kind] ?? o.kind} · {statusLabels[o.status] ?? o.status}{o.connectionName ? ` · ${o.connectionName}` : ''}</span><time dateTime={o.created_at}>{new Date(o.created_at).toLocaleString(i18n.language)}</time></li>)}</ul>
      </section>
    </>}
    <footer className="ai-muted">Synca · <Link to="/">{t('ai_page.text_066')}</Link> · <a href={zh ? '/zh-hans/privacy-policy' : '/en/privacy-policy'}>{t('ai_page.text_067')}</a></footer>
    {planVisible && <PlanDialog onClose={() => setPlanVisible(false)} />}
    {previewVisible && <Modal title={t('ai_page.text_068')} message="" confirmText={t('ai_page.text_069')} onConfirm={() => setPreviewVisible(false)} onCancel={() => setPreviewVisible(false)} hideCancel neutral className="ai-prompt-modal">
      <div className="ai-prompt-scroll"><p>{connectionPrompt}</p></div>
    </Modal>}
  </div></main>;
}
