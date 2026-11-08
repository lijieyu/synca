import { PersonIcon } from './PersonIcon';
import { useState } from 'react';

import { useTranslation } from 'react-i18next';
import { PlanContent, StorageUsage } from './PlanDialog';
import { useAuth } from '../contexts/AuthContext';
import { Modal } from './Modal';
import { api } from '../api/client';
import { version } from '../../package.json';

export function ShellPanel({ kind, email, onClose, onLogout }: {
  kind: 'account' | 'feedback' | 'about'; email: string | null; onClose: () => void; onLogout: () => void;
}) {
  const { logout } = useAuth();
  const [deleteConfirm, setDeleteConfirm] = useState(false);
  const [discardConfirm, setDiscardConfirm] = useState(false);
  const { t, i18n } = useTranslation();
  const [content, setContent] = useState('');
  const [replyEmail, setReplyEmail] = useState(email ?? '');
  const [images, setImages] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [sent, setSent] = useState(false);
  const locale = i18n.language.startsWith('zh') ? 'zh-hans' : 'en';
  const close = () => { if (busy) return; if (kind === 'feedback' && !sent && (content.trim() || images.length || replyEmail !== (email ?? ''))) setDiscardConfirm(true); else onClose(); };
  const submit = async (e: React.FormEvent) => {
    e.preventDefault(); if (busy) return; setError(''); setBusy(true);
    try { await api.submitFeedback(content.trim(), replyEmail.trim(), images); setSent(true); }
    catch { setError(t('navigation.feedback_failed')); } finally { setBusy(false); }
  };
  return <><Modal title={t(kind === 'account' ? 'preferences.account_plan' : kind === 'feedback' ? 'message_list.feedback' : 'message_list.about')}
    hideActions={kind === 'account' || kind === 'about'}
    scrollBody={kind === 'account' || kind === 'feedback'}
    className={kind === 'feedback' ? 'feedback-modal' : `${kind}-modal`} size={kind === 'about' ? 'compact' : 'standard'}
    closeLabel={t('navigation.close')} closeDisabled={busy}
    neutral={kind !== 'feedback' || sent} message="" confirmText={t(kind === 'feedback' && !sent ? 'feedback.submit' : 'navigation.close')}
    cancelText={t('common.cancel')} hideCancel={kind !== 'feedback' || sent}
    confirmDisabled={busy || (kind === 'feedback' && !sent && !content.trim())} cancelDisabled={busy}
    onConfirm={() => { if (kind === 'feedback' && !sent) document.querySelector<HTMLFormElement>('#feedback-form')?.requestSubmit(); else close(); }} onCancel={close}>
    {kind === 'account' && <div className="account-panel">
      <div className="account-summary"><div className="account-identity">
        <span className="account-avatar" aria-hidden="true"><PersonIcon size={28} /></span>
        <div className="account-details">
          <p className="account-email">{email || t('navigation.account')}</p>
        </div>
      </div>
      <StorageUsage /></div>
      <PlanContent showStorage={false} />
      <div className="account-danger-actions"><button className="account-text-action account-text-action-destructive" onClick={() => setDeleteConfirm(true)}>{t('account.delete_action')}</button><button className="account-text-action" onClick={onLogout}>{t('message_list.logout')}</button></div>
      {error && <p role="alert">{error}</p>}
    </div>}
    {kind === 'about' && <div className="about-panel">
      <div className="about-identity"><img src="/logo.png?v=a2" alt="" width={48} height={48} /><div><h4>Synca</h4><p>{t('navigation.web')} · {version}</p></div></div>
      <p className="about-description">{t('app.slogan')}</p>
      <nav className="shell-links" aria-label={t('message_list.about')}><a href={`/${locale}/privacy-policy`} target="_blank" rel="noopener noreferrer">{t('navigation.privacy')}</a><a href={`/${locale}/support`} target="_blank" rel="noopener noreferrer">{t('navigation.support')}</a></nav>
      <p className="about-registration">浙ICP备2026013056号-3A</p>
    </div>}
    {kind === 'feedback' && (sent ? <p role="status">{t('navigation.feedback_sent')}</p> : <form id="feedback-form" className="shell-form" onSubmit={submit}>
      <label>{t('feedback.content_title')}<textarea required maxLength={2000} value={content} onChange={e => setContent(e.target.value)} disabled={busy} placeholder={t('feedback.content_placeholder')} /></label>
      <label>{t('feedback.email_title')}<input required type="email" maxLength={320} value={replyEmail} onChange={e => setReplyEmail(e.target.value)} disabled={busy} /></label>
      <label>{t('feedback.images_title')}<input type="file" accept="image/jpeg,image/png,image/gif,image/webp,image/heic,image/heif" multiple disabled={busy} onChange={e => {
        const files = [...(e.target.files ?? [])];
        if (files.length > 3 || files.some(f => f.size > 20 * 1024 * 1024)) { setError(t('navigation.feedback_images')); e.target.value = ''; setImages([]); return; }
        setError(''); setImages(files);
      }} /></label><small>{t('navigation.feedback_images')}</small>
      {error && <p role="alert">{error}</p>}
    </form>)}
  </Modal>
    {discardConfirm && <Modal title={t('message_edit.discard_title')} message="" confirmText={t('message_edit.discard')} cancelText={t('common.cancel')} destructive onCancel={() => setDiscardConfirm(false)} onConfirm={onClose} />}
    {deleteConfirm && <Modal title={t('account.delete_confirm_title')} message={t('account.delete_confirm_message')} confirmText={t('account.delete_action')} cancelText={t('common.cancel')} destructive confirmDisabled={busy} closeDisabled={busy} cancelDisabled={busy}
      onCancel={() => { if (!busy) setDeleteConfirm(false); }} onConfirm={() => { if (busy) return; setBusy(true); void api.deleteAccount().then(() => { logout(); onClose(); }).catch(() => { setError(t('account.delete_failed_message')); setDeleteConfirm(false); }).finally(() => setBusy(false)); }} />}
  </>;
}
