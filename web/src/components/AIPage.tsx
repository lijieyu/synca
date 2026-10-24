import { useCallback, useEffect, useState } from 'react';
import { ArrowUpRight, Copy, Check, Sparkles, ShieldCheck, MessageSquare, Link2 } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuth } from '../contexts/AuthContext';
import { LoginView } from './LoginView';
import { Modal } from './Modal';
import './AIPage.css';

type Scope = 'read' | 'create' | 'update' | 'delete' | 'attachments';
type Connection = { id: string; name: string; scopes: Scope[]; expires_at: string; revoked_at: string | null; last_used_at: string | null };
type Operation = { id: string; kind: string; status: string; created_at: string; connectionName?: string };
type Confirmation = { id: string; status: string; expiresAt: string; items?: { id: string; preview: string }[] };
type Authorization = { authorizationDays: number; autoRefresh: boolean; refreshIdleDays: number; clientName: string; scopes: Scope[]; redirectUri: string };

export function AIPage() {
  const { token, isAuthenticated } = useAuth();
  const { i18n } = useTranslation();
  const zh = i18n.language.startsWith('zh');
  const t = (cn: string, en: string) => zh ? cn : en;
  const labels: Record<Scope, string> = { read: t('读取记录与用量', 'Read records and usage'), create: t('新增记录和分类', 'Create records and categories'),
    update: t('编辑、分类与处理状态', 'Edit, categorize and complete'), delete: t('申请删除记录、删除分类', 'Request record deletion; delete categories'), attachments: t('传输图片和文件', 'Transfer images and files') };
  const actionLabels: Record<string, string> = {
    create_message: t('新增文字', 'Created text'), create_attachment: t('新增附件', 'Created attachment'), upload_attachment: t('上传附件', 'Uploaded attachment'),
    update_messages: t('修改记录', 'Updated records'), delete_messages: t('删除记录', 'Delete records'),
    category_create: t('新建分类', 'Created category'), category_update: t('修改分类', 'Updated category'), category_delete: t('删除分类', 'Deleted category'), category_reorder: t('分类排序', 'Reordered categories'),
  };
  const statusLabels: Record<string, string> = { pending: t('待确认', 'Pending approval'), completed: t('已完成', 'Completed'), cancelled: t('已取消', 'Cancelled'), expired: t('已过期', 'Expired') };
  const params = new URLSearchParams(window.location.search);
  const authorize = params.get('authorize');
  const confirm = params.get('confirm');
  const [connections, setConnections] = useState<Connection[]>([]);
  const [operations, setOperations] = useState<Operation[]>([]);
  const [authorization, setAuthorization] = useState<Authorization | null>(null);
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
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
  const [loginVisible, setLoginVisible] = useState(Boolean(authorize || confirm));
  const endpoint = `${window.location.origin}/mcp`;
  const connectionPrompt = t(
    `请帮我连接 Synca，使用远程 MCP 服务 ${endpoint}（Streamable HTTP），通过 OAuth 登录授权。请使用你所在应用提供的 MCP 安装和连接能力；若已安装请直接连接，不要重复添加。请引导我在当前软件内完成 MCP 配置和 OAuth 授权：名称 Synca，服务器地址 ${endpoint}，传输方式 Streamable HTTP，身份验证 OAuth。若无法直接添加，请明确说明，并根据当前软件实际界面逐步告诉我在哪里添加、每项填什么、如何点击连接，再引导我打开官方 Synca 登录授权页，亲自登录并确认所需权限。不要编造菜单路径；不确定时请先询问软件版本或让我提供当前界面。不要让我把密码、验证码或访问令牌发到对话里。不要把提供配置说明当作安装成功。连接成功后，读取最近 5 条 Synca 记录验证连接，不要修改或删除内容。`,
    `Please connect me to Synca using its remote MCP server ${endpoint} (Streamable HTTP) with OAuth authorization. Use this app's supported MCP installation and connection capabilities; reuse an existing connection instead of adding a duplicate. Guide me through configuration and OAuth authorization inside the app I am currently using: name Synca, server URL ${endpoint}, transport Streamable HTTP, authentication OAuth. If you cannot add it directly, say so and guide me step by step through the actual app settings, what to enter, and how to connect, then open the official Synca sign-in and consent page for me to sign in and approve permissions. Do not invent menu paths; if unsure, ask for the app version or current screen. Never ask me to paste passwords, verification codes, or access tokens into chat. Providing instructions does not mean installation succeeded. After connecting, read my 5 most recent Synca records to verify the connection without changing or deleting anything.`,
  );
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
    document.title = zh ? '连接 AI · Synca' : 'Connect AI · Synca';
    return () => { document.title = 'Synca'; };
  }, [zh]);
  useEffect(() => {
    if (!token) return;
    let active = true;
    setLoading(true);
    const load = async () => {
      const [c, o, a, d] = await Promise.all([
        request<{ connections: Connection[] }>('connections'), request<{ operations: Operation[] }>('operations'),
        authorize ? request<Authorization>(`authorization/${encodeURIComponent(authorize)}`) : null,
        confirm ? request<Confirmation>(`confirmations/${encodeURIComponent(confirm)}`) : null,
      ]);
      if (active) { setConnections(c.connections); setOperations(o.operations); setAuthorization(a); setConfirmation(d); }
    };
    void load().catch(e => { if (active) setError(String(e.message)); }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [token, request, authorize, confirm]);
  const act = async (fn: () => Promise<void>) => {
    if (busy) return;
    setBusy(true); setError(''); setNotice('');
    try { await fn(); } catch (e) { setError(e instanceof Error ? e.message : String(e)); } finally { setBusy(false); }
  };
  const copy = (value: string) => act(async () => { setCopied(false); await navigator.clipboard.writeText(value); setCopied(true); });
  const activeConnections = connections.filter(c => !c.revoked_at && new Date(c.expires_at).getTime() > Date.now());
  return <main className={`ai-page${previewVisible ? ' ai-preview-open' : ''}`} inert={previewVisible}><div className="ai-content">
    <nav className="ai-nav" aria-label={t('导航', 'Navigation')}><Link className="ai-brand" to="/"><img src="/logo.png" alt="" />Synca</Link><Link className="ai-back" to="/">{t('打开 Synca', 'Open Synca')} <ArrowUpRight size={16} /></Link></nav>
    {!authorize && !confirm && <><div className="ai-intro-grid"><header className="ai-hero"><span className="ai-eyebrow"><Sparkles size={15} /> SYNCA × AI</span>
      <h1>{t('随手记下，\n让 AI 接着处理。', 'Capture a thought.\nLet AI take it further.')}</h1>
      <p>{t('在支持 MCP 的 AI 应用中，查找、整理你的记录，并把讨论结果保存回 Synca。手机、Mac 和 Web 自动同步。', 'Find and organize your records in AI apps that support MCP. Save the conversation’s conclusions back to Synca, synced across phone, Mac and web.')}</p>
      <div className="ai-assurance"><ShieldCheck size={17} />{t('由你授权，随时断开', 'Your permission. Your control.')}</div>
    </header>
    <section className="ai-card ai-connect" id="connect"><div className="ai-connect-icon"><Link2 size={24} /></div><span className="ai-step-label">{t('只需三步', 'THREE SIMPLE STEPS')}</span><h2>{t('连接你的 AI 应用', 'Connect your AI app')}</h2>
      <ol><li>{t('复制下面的指令，发给你正在使用的 AI。', 'Copy the instruction below and send it to your AI.')}</li>
        <li>{t('跟随 AI 指导，在当前软件内完成配置与授权。', 'Follow your AI’s guidance to configure and authorize Synca in your current app.')}</li>
        <li>{t('回到对话，让 AI 查找或整理你的记录。', 'Return to the conversation to find and organize your records.')}</li></ol>
      <button className="ai-primary" disabled={busy} onClick={() => void copy(connectionPrompt)}>{copied ? <Check size={18} aria-hidden="true" /> : <Copy size={18} aria-hidden="true" />}<span aria-live="polite">{copied ? t('已复制', 'Copied') : t('复制指令给AI', 'Copy instructions for AI')}</span></button>
      <p className="ai-muted">{t('无需先在这里登录，也不用生成或复制密钥。若 AI 无法自动添加连接，它会引导你完成必要的设置；是否支持取决于应用和版本。', 'No sign-in here or API key is needed to start. If your AI cannot add the connection automatically, it will guide you through the required setup. Support depends on the app and version.')}</p>
      <button className="ai-preview-trigger" aria-haspopup="dialog" onClick={() => setPreviewVisible(true)}>{t('查看将复制的指令', 'Preview the instruction')}<ArrowUpRight size={15} aria-hidden="true" /></button>
    </section></div>
    <section className="ai-examples" aria-label={t('使用示例', 'Examples')}>
      {[t('“帮我整理本周的灵感”', '“Organize this week’s ideas”'), t('“找出关于新项目的记录”', '“Find my notes about the new project”'), t('“把这个结论保存到 Synca”', '“Save this conclusion to Synca”')].map(v => <p key={v}><MessageSquare size={18} aria-hidden="true" />{v}</p>)}
    </section>
    </>}
    {(authorize || confirm || isAuthenticated) && <div aria-live="polite" role="status" className="ai-notice">{notice}</div>}
    {error && <div role="alert" className="ai-error">{t('操作未完成：', 'Could not complete: ')}{error}<button onClick={() => window.location.reload()}>{t('重新加载', 'Reload')}</button></div>}
    {loading && <p role="status">{t('正在加载连接信息…', 'Loading connections…')}</p>}
    {!isAuthenticated && <section className={`ai-card ${!authorize && !confirm ? 'ai-manage' : ''}`}><h2>{authorize || confirm ? t('登录 Synca 以继续', 'Sign in to Synca to continue') : t('管理已连接的 AI', 'Manage connected AI apps')}</h2>
      <p>{t('授权的 AI 服务将接收你允许访问的内容。你可以随时撤销后续访问，但无法收回对方已经读取的数据。', 'Authorized AI services receive the content you permit. You can revoke future access, but cannot recall data already read.')}</p>
      {!loginVisible ? <button className="ai-primary" onClick={() => setLoginVisible(true)}>{t('登录 Synca', 'Sign in to Synca')}</button> : <div className="ai-login"><LoginView showAILink={false} /></div>}
    </section>}
    {isAuthenticated && authorization && <section className="ai-card ai-consent"><h2>{t('授权连接', 'Authorize connection')} · {authorization.clientName}</h2>
      <p>{t('该应用名称由接入方提供。请确认它是你正在连接的应用。', 'This name is supplied by the connecting application. Verify that it is the app you intended to connect.')}</p>
      <p className="ai-wrap">{t('返回地址：', 'Return address: ')}{authorization.redirectUri}</p>
      <ul>{authorization.scopes.map(s => <li key={s}>{labels[s]}</li>)}</ul>
      <p>{t(`授权最长 ${authorization.authorizationDays} 天，可随时撤销。外部 AI 将接收获准访问的数据。`, `Authorization lasts up to ${authorization.authorizationDays} days and can be revoked at any time. The external AI receives permitted data.`)}</p>
      <p>{authorization.autoRefresh ? t(`支持自动续期；连续 ${authorization.refreshIdleDays} 天未刷新或授权满一年后，需要重新授权。`, `Automatic refresh is supported. Reauthorize after ${authorization.refreshIdleDays} days without refreshing or after one year.`) : t('当前应用未申请自动续期，访问令牌 30 天后到期。请使用支持自动续期的配置重新连接。', 'This app did not request automatic refresh. Access expires in 30 days; reconnect with a refresh-enabled configuration.')}</p>
      <div className="ai-actions">{[true, false].map(approve => <button key={String(approve)} className={approve ? 'ai-primary' : ''} disabled={busy} onClick={() => void act(async () => {
        const result = await request<{ redirectUrl: string }>(`authorization/${encodeURIComponent(authorize!)}`, 'POST', { approve });
        window.location.assign(result.redirectUrl);
      })}>{approve ? t('允许连接', 'Allow connection') : t('拒绝', 'Deny')}</button>)}</div>
    </section>}
    {isAuthenticated && confirmation && <section className="ai-card"><h2>{t('确认删除记录', 'Confirm record deletion')}</h2>
      <p>{t('只删除下面列出的记录。删除不可撤销；记录在此期间发生变化时，需要重新申请。', 'Only the listed records will be deleted. This cannot be undone; changed records require a new request.')}</p>
      <p>{t('状态：', 'Status: ')}{statusLabels[confirmation.status] ?? confirmation.status} · {t('有效至：', 'Expires: ')}{new Date(confirmation.expiresAt).toLocaleString(zh ? 'zh-CN' : 'en-US')}</p>
      <ol className="ai-preview">{confirmation.items?.map(item => <li key={item.id}>{item.preview}</li>)}</ol>
      {confirmation.status === 'pending' && <div className="ai-actions">{[true, false].map(approve => <button key={String(approve)} disabled={busy || Date.parse(confirmation.expiresAt) <= Date.now()} className={approve ? 'ai-danger' : ''} onClick={() => void act(async () => {
        await request(`confirmations/${encodeURIComponent(confirm!)}`, 'POST', { approve });
        setConfirmation({ ...confirmation, status: approve ? 'completed' : 'cancelled' });
        setNotice(approve ? t('已删除所选记录', 'Selected records deleted') : t('已取消', 'Cancelled')); await refresh();
      })}>{approve ? t(`确认删除 ${confirmation.items?.length ?? 0} 条`, `Delete ${confirmation.items?.length ?? 0} records`) : t('取消', 'Cancel')}</button>)}</div>}
    </section>}
    {isAuthenticated && !authorize && !confirm && <>
      <section className="ai-card"><h2>{t('已连接的应用', 'Connected apps')}</h2>
        {!activeConnections.length && <p className="ai-muted">{t('还没有有效连接。', 'No active connections yet.')}</p>}
        {activeConnections.map(c => <article className="ai-connection" key={c.id}><div><h3>{c.name}</h3><p>{c.scopes.map(s => labels[s]).join(' · ')}</p>
          <p className="ai-muted">{t('到期：', 'Expires: ')}{new Date(c.expires_at).toLocaleDateString(zh ? 'zh-CN' : 'en-US')} · {t('最近访问：', 'Last access: ')}{c.last_used_at ? new Date(c.last_used_at).toLocaleString(zh ? 'zh-CN' : 'en-US') : t('尚未使用', 'Not used yet')}</p></div>
          <button disabled={busy} onClick={() => void act(async () => { await request(`connections/${c.id}`, 'DELETE'); await refresh(); setNotice(t('已撤销连接', 'Connection revoked')); })}>{t('撤销', 'Revoke')}</button></article>)}
      </section>
      <section className="ai-card"><h2>{t('最近操作', 'Recent operations')}</h2>{!operations.length && <p className="ai-muted">{t('暂无操作记录。', 'No operations yet.')}</p>}
        <ul className="ai-log">{operations.map(o => <li key={o.id}><span>{actionLabels[o.kind] ?? o.kind} · {statusLabels[o.status] ?? o.status}{o.connectionName ? ` · ${o.connectionName}` : ''}</span><time dateTime={o.created_at}>{new Date(o.created_at).toLocaleString(zh ? 'zh-CN' : 'en-US')}</time></li>)}</ul>
      </section>
    </>}
    <footer className="ai-muted">Synca · <Link to="/">{t('返回记录', 'Back to records')}</Link> · <a href={zh ? '/zh-hans/privacy-policy' : '/en/privacy-policy'}>{t('隐私政策', 'Privacy policy')}</a></footer>
    {previewVisible && <Modal title={t('将复制的指令', 'Instruction preview')} message="" confirmText={t('关闭', 'Close')} onConfirm={() => setPreviewVisible(false)} onCancel={() => setPreviewVisible(false)} hideCancel neutral className="ai-prompt-modal">
      <div className="ai-prompt-scroll"><p>{connectionPrompt}</p></div>
    </Modal>}
  </div></main>;
}
