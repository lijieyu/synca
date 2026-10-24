import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Modal } from './Modal';
import { api } from '../api/client';

export function ShellPanel({ kind, email, isAdmin, onClose, onLogout }: {
  kind: 'account' | 'feedback' | 'about'; email: string | null; isAdmin: boolean; onClose: () => void; onLogout: () => void;
}) {
  const { t, i18n } = useTranslation();
  const [content, setContent] = useState('');
  const [replyEmail, setReplyEmail] = useState(email ?? '');
  const [images, setImages] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [sent, setSent] = useState(false);
  const locale = i18n.language.startsWith('zh') ? 'zh-hans' : 'en';
  return <Modal title={t(kind === 'account' ? 'navigation.account' : kind === 'feedback' ? 'message_list.feedback' : 'message_list.about')}
    message="" confirmText={t('navigation.close')} hideCancel onConfirm={() => { if (!busy) onClose(); }} onCancel={() => { if (!busy) onClose(); }}>
    {kind === 'account' && <div className="shell-form"><p>{t('navigation.provider')}</p><p>{email || '—'}</p>
      {isAdmin && <a href="/admin" target="_blank" rel="noopener noreferrer">{t('navigation.admin')}</a>}
      <button onClick={onLogout}>{t('message_list.logout')}</button></div>}
    {kind === 'about' && <div className="shell-form"><p>{t('navigation.about')}</p><p>Synca · {t('navigation.web')}</p>
      <div className="shell-links"><a href={`/${locale}/privacy-policy`}>{t('navigation.privacy')}</a><a href={`/${locale}/support`}>{t('navigation.support')}</a></div></div>}
    {kind === 'feedback' && (sent ? <p role="status">{t('navigation.feedback_sent')}</p> : <form className="shell-form" onSubmit={async e => {
      e.preventDefault(); if (busy) return; setError(''); setBusy(true);
      try { await api.submitFeedback(content.trim(), replyEmail.trim(), images); setSent(true); }
      catch { setError(t('navigation.feedback_failed')); } finally { setBusy(false); }
    }}>
      <label>{t('feedback.content_title')}<textarea required maxLength={2000} value={content} onChange={e => setContent(e.target.value)} disabled={busy} placeholder={t('feedback.content_placeholder')} /></label>
      <label>{t('feedback.email_title')}<input required type="email" maxLength={320} value={replyEmail} onChange={e => setReplyEmail(e.target.value)} disabled={busy} /></label>
      <label>{t('feedback.images_title')}<input type="file" accept="image/jpeg,image/png,image/gif,image/webp,image/heic,image/heif" multiple disabled={busy} onChange={e => {
        const files = [...(e.target.files ?? [])];
        if (files.length > 3 || files.some(f => f.size > 20 * 1024 * 1024)) { setError(t('navigation.feedback_images')); e.target.value = ''; setImages([]); return; }
        setError(''); setImages(files);
      }} /></label><small>{t('navigation.feedback_images')}</small>
      {error && <p role="alert">{error}</p>}
      <button type="submit" disabled={busy || !content.trim()}>{busy ? t('message_list.loading', 'Loading…') : t('feedback.submit')}</button>
    </form>)}
  </Modal>;
}
