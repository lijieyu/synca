import { useEmailAvailability } from '../auth/useEmailAvailability';
import { LoginMethods } from './LoginMethods';
import { DeveloperSocialLink } from './DeveloperSocialLink';
import { PersonIcon } from './PersonIcon';
import { useContext, useRef, useState } from 'react';
import { ArrowUpRight, ChevronDown, ChevronRight, ImagePlus, X } from 'lucide-react';
import { SettingsSurface } from './SettingsSurface';

import { useTranslation } from 'react-i18next';
import { AccountPlanLabel, PlanContent, StorageUsage } from './PlanDialog';
import { useAuth } from '../contexts/AuthContext';
import { Modal } from './Modal';
import { api } from '../api/client';
import { version } from '../../package.json';

const maxFeedbackImages = 3;
const maxFeedbackImageBytes = 20 * 1024 * 1024;
const feedbackImageTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif'];
const feedbackImageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif'];

function InlinePanel({ children }: { children?: React.ReactNode }) { return <>{children}</> }

export type AccountPage = 'overview' | 'plan' | 'methods' | 'manage';

export function ShellPanel({ kind, email, onClose, onLogout, inline, accountPage, onAccountPageChange }: {
  kind: 'account' | 'feedback' | 'about'; email: string | null; onClose: () => void; onLogout: () => void; inline?: boolean; accountPage?: AccountPage; onAccountPageChange?: (page: AccountPage) => void;
}) {
  const emailAvailable = useEmailAvailability();
  const settingsSurface = useContext(SettingsSurface);
  const { logout, accessStatus } = useAuth();
  const [deleteConfirm, setDeleteConfirm] = useState(false);
  const [discardConfirm, setDiscardConfirm] = useState(false);
  const { t, i18n } = useTranslation();
  const [content, setContent] = useState('');
  const [replyEmail, setReplyEmail] = useState(email ?? '');
  const [images, setImages] = useState<File[]>([]);
  const filePicker = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [sent, setSent] = useState(false);
  const locale = i18n.language.startsWith('zh') ? 'zh-hans' : 'en';
  function addImages(event: React.ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(event.currentTarget.files ?? []);
    event.currentTarget.value = '';
    if (!selected.length) return;
    const unsupported = selected.some(file => file.type
      ? !feedbackImageTypes.includes(file.type)
      : !feedbackImageExtensions.some(ext => file.name.toLowerCase().endsWith(ext)));
    if (unsupported || selected.some(file => file.size > maxFeedbackImageBytes) || images.length + selected.length > maxFeedbackImages) {
      setError(t(unsupported ? 'review.page.image_formats' : 'navigation.feedback_images'));
      return;
    }
    setError('');
    setImages([...images, ...selected]);
  }
  const close = () => { if (busy) return; if (kind === 'feedback' && !sent && (content.trim() || images.length || replyEmail !== (email ?? ''))) setDiscardConfirm(true); else onClose(); };
  const submit = async (e: React.FormEvent) => {
    e.preventDefault(); if (busy) return; setError(''); setBusy(true);
    try { await api.submitFeedback(content.trim(), replyEmail.trim(), images); setSent(true); }
    catch { setError(t('navigation.feedback_failed')); } finally { setBusy(false); }
  };
  const Panel = inline ? InlinePanel : Modal;
  return <><Panel title={t(kind === 'account' ? 'preferences.account_plan' : kind === 'feedback' ? 'message_list.feedback' : 'message_list.about')}
    hideActions={kind === 'account' || kind === 'about'}
    scrollBody={kind === 'account' || kind === 'feedback'}
    className={kind === 'feedback' ? 'feedback-modal' : `${kind}-modal`} size={kind === 'about' ? 'compact' : 'standard'}
    closeLabel={t('navigation.close')} closeDisabled={busy}
    neutral={kind !== 'feedback' || sent} message="" confirmText={t(kind === 'feedback' && !sent ? 'feedback.submit' : 'navigation.close')}
    cancelText={t('common.cancel')} hideCancel={kind !== 'feedback' || sent}
    confirmDisabled={busy || (kind === 'feedback' && !sent && !content.trim())} cancelDisabled={busy}
    onConfirm={() => { if (kind === 'feedback' && !sent) document.querySelector<HTMLFormElement>('#feedback-form')?.requestSubmit(); else close(); }} onCancel={close}>
    {kind === 'account' && accountPage && <div className="account-panel account-pages">
      {accountPage === 'overview' && <>
        <div className="account-identity">
          <span className="account-avatar" aria-hidden="true"><PersonIcon size={24} /></span>
          <div className="account-details"><p className="account-email" title={email || undefined}>{email || t('navigation.account')}</p><p className="account-plan-subtitle"><AccountPlanLabel /></p></div>
        </div>
        <h3>{t('access.current_plan_title')}</h3>
        <div className="account-group"><button className="account-row" onClick={() => onAccountPageChange?.('plan')}><span><AccountPlanLabel /></span><span className="account-row-detail">{t(accessStatus?.isUnlimited ? 'review.page.benefits' : 'review.page.compare_plans')}<ChevronRight size={16} aria-hidden="true" /></span></button></div>
        {accessStatus && <div className="account-usage-group">
          {Number.isFinite(accessStatus.todayUsed) && <p className="account-daily-usage"><span>{t('preferences.daily_usage')}</span><span>{accessStatus.todayLimit == null ? accessStatus.todayUsed : `${accessStatus.todayUsed} / ${accessStatus.todayLimit}`}</span></p>}
          <StorageUsage />
        </div>}
        <h3>{t('navigation.account')}</h3>
        <div className="account-group">
          {emailAvailable && <button className="account-row" onClick={() => onAccountPageChange?.('methods')}><span>{t('email_auth.methods')}</span><ChevronRight size={16} aria-hidden="true" /></button>}
          <button className="account-row" onClick={() => onAccountPageChange?.('manage')}><span>{t('review.page.manage_account')}</span><ChevronRight size={16} aria-hidden="true" /></button>
          <button className="account-row" onClick={onLogout}>{t('message_list.logout')}</button>
        </div>
      </>}
      {accountPage === 'plan' && <PlanContent showStorage={false} />}
      {accountPage === 'methods' && <LoginMethods />}
      {accountPage === 'manage' && <div className="account-group"><button className="account-row account-text-action-destructive" onClick={() => setDeleteConfirm(true)}>{t('account.delete_action')}</button></div>}
      {error && <p role="alert">{error}</p>}
    </div>}
    {kind === 'account' && !accountPage && <div className="account-panel">
      <div className="account-summary"><div className="account-identity">
        <span className="account-avatar" aria-hidden="true"><PersonIcon size={28} /></span>
        <div className="account-details">
          <p className="account-email" title={email || undefined}>{email || t('navigation.account')}</p><p className="account-plan-subtitle"><AccountPlanLabel /></p>
        </div>
      </div>
      {accessStatus && Number.isFinite(accessStatus.todayUsed) && <p className="account-daily-usage"><span>{t('preferences.daily_usage')}</span><span>{accessStatus.todayLimit == null ? accessStatus.todayUsed : `${accessStatus.todayUsed} / ${accessStatus.todayLimit}`}</span></p>}
      <StorageUsage /></div>
      {accessStatus && <details className="account-benefits"><summary>{t(accessStatus.isUnlimited ? 'review.page.benefits' : 'review.page.compare_plans')}<ChevronDown size={16} aria-hidden="true" /></summary><PlanContent showStorage={false} /></details>}
      {emailAvailable && <LoginMethods />}
      <button className="account-session-action" onClick={onLogout}>{t('message_list.logout')}</button>
      <details className="account-management"><summary>{t('review.page.manage_account')}<ChevronDown size={16} aria-hidden="true" /></summary>
        <button className="account-text-action account-text-action-destructive" onClick={() => setDeleteConfirm(true)}>{t('account.delete_action')}</button>
      </details>
      {error && <p role="alert">{error}</p>}
    </div>}
    {kind === 'about' && <div className="about-panel">
      <div className="about-identity"><img src="/logo.png?v=a2" alt="" width={48} height={48} /><div><h4>Synca</h4><p>{window.syncaDesktop?.platform ?? t('navigation.web')} · {window.syncaDesktop?.version ?? version}</p></div></div>
      <p className="about-description">{t('app.slogan')}</p>
      <nav className="about-links" aria-label={t('message_list.about')}>
        <a href={`/${locale}/privacy-policy`} target="_blank" rel="noopener noreferrer">{t('navigation.privacy')}<ArrowUpRight size={16} aria-hidden="true" /></a>
        <a href={`/${locale}/support`} target="_blank" rel="noopener noreferrer">{t('navigation.support')}<ArrowUpRight size={16} aria-hidden="true" /></a>
        <DeveloperSocialLink />
      </nav>
      <p className="about-registration">浙ICP备2026013056号-3A</p>
    </div>}
    {kind === 'feedback' && (sent ? <p role="status">{t('navigation.feedback_sent')}</p> : <form id="feedback-form" className="shell-form" onSubmit={submit}>
      <label>{t('feedback.content_title')}<textarea required maxLength={2000} value={content} onChange={e => setContent(e.target.value)} disabled={busy} placeholder={t('feedback.content_placeholder')} /></label>
      <label>{t('feedback.email_title')}<input required type="email" maxLength={320} value={replyEmail} onChange={e => setReplyEmail(e.target.value)} disabled={busy} /></label>
      <div className="feedback-attachments">
        <p>{t('feedback.images_title')}</p>
        <input ref={filePicker} type="file" hidden accept={[...feedbackImageTypes, ...feedbackImageExtensions].join(',')} multiple disabled={busy} onChange={addImages} />
        <button type="button" className="feedback-add" disabled={busy || images.length >= maxFeedbackImages} onClick={() => filePicker.current?.click()} aria-describedby="feedback-image-hint"><ImagePlus size={16} aria-hidden="true" />{t(images.length ? 'feedback.add_more_images' : 'feedback.add_images')}</button>
        <small id="feedback-image-hint">{t('navigation.feedback_images')}</small>
        {images.length > 0 && <ul>{images.map((file, index) => <li key={index}><span>{file.name}</span><button type="button" disabled={busy} aria-label={t('review.page.remove_image', {name: file.name})} onClick={() => { setImages(images.filter((_, i) => i !== index)); setError(''); }}><X size={16} aria-hidden="true" /></button></li>)}</ul>}
      </div>
      <div className="feedback-social"><DeveloperSocialLink /></div>
      {error && <p role="alert">{error}</p>}
    </form>)}
  </Panel>
    {discardConfirm && <Modal title={t('message_edit.discard_title')} message="" confirmText={t('message_edit.discard')} cancelText={t('message_edit.keep')} destructive onCancel={() => { setDiscardConfirm(false); settingsSurface?.continueEditing(); requestAnimationFrame(() => document.querySelector<HTMLTextAreaElement>('#feedback-form textarea')?.focus()); }} onConfirm={onClose} />}
    {deleteConfirm && <Modal title={t('account.delete_confirm_title')} message={t('account.delete_confirm_message')} confirmText={t('account.delete_action')} cancelText={t('common.cancel')} destructive confirmDisabled={busy} closeDisabled={busy} cancelDisabled={busy}
      onCancel={() => { if (!busy) setDeleteConfirm(false); }} onConfirm={() => { if (busy) return; setBusy(true); void api.deleteAccount().then(() => { logout(); onClose(); }).catch(() => { setError(t('account.delete_failed_message')); setDeleteConfirm(false); }).finally(() => setBusy(false)); }} />}
  </>;
}
