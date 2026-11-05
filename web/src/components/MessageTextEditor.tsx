import React, { useEffect, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { api, MessageEditError, SessionExpiredError, type SyncaMessage } from '../api/client';
import { Modal } from './Modal';

interface Props {
  message: SyncaMessage;
  onCancel: () => void;
  onSaved: (updated: SyncaMessage) => void;
}

/** Owned by the list, so polling, category changes and row reordering preserve the draft. */
export const MessageTextEditor: React.FC<Props> = ({ message, onCancel, onSaved }) => {
  const { t } = useTranslation();
  const [draft, setDraft] = useState(message.textContent ?? '');
  const [errorMessage, setErrorMessage] = useState('');
  const [sessionExpired, setSessionExpired] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [confirmDiscard, setConfirmDiscard] = useState(false);
  const saveInFlight = useRef(false);
  const inputId = React.useId();
  const inputRef = useRef<HTMLTextAreaElement>(null);
  useEffect(() => api.retainEditingDraft(() => setSessionExpired(true)), []);
  useEffect(() => {
    if (!isSaving && (errorMessage || sessionExpired)) inputRef.current?.focus();
  }, [isSaving, errorMessage, sessionExpired]);
  const hasChanges = draft !== (message.textContent ?? '');
  const canSave = hasChanges && !isSaving && !sessionExpired && Boolean(draft.trim()) && draft.length <= 2000;
  useEffect(() => {
    if (!hasChanges) return;
    const preserveDraft = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ''; };
    window.addEventListener('beforeunload', preserveDraft);
    return () => window.removeEventListener('beforeunload', preserveDraft);
  }, [hasChanges]);
  const cancel = () => {
    if (saveInFlight.current) return;
    if (hasChanges) setConfirmDiscard(true);
    else onCancel();
  };
  const save = async () => {
    if (!canSave || saveInFlight.current) return;
    saveInFlight.current = true; setIsSaving(true); setErrorMessage('');
    try {
      const updated = await api.updateMessageText(message.id, draft, message.updatedAt);
      onSaved(updated);
    } catch (error) {
      if (error instanceof SessionExpiredError) setSessionExpired(true);
      setErrorMessage(t(error instanceof SessionExpiredError ? 'message_edit.session_expired' : error instanceof MessageEditError
        ? error.code === 'message_edit_conflict' ? 'message_edit.conflict' : 'message_edit.unavailable'
        : 'message_edit.failed'));
    } finally { saveInFlight.current = false; setIsSaving(false); }
  };

  return <>
    <Modal title={t('message_edit.title')} message=""
      confirmText={t(isSaving ? 'message_edit.saving' : 'common.save')} cancelText={t('common.cancel')}
      onConfirm={() => void save()} onCancel={cancel} confirmDisabled={!canSave} cancelDisabled={isSaving}
      className="message-text-editor" closeDisabled={isSaving}>
      <label className="message-editor-label" htmlFor={inputId}>{t('message_edit.content')}</label>
      <textarea ref={inputRef} id={inputId} className="message-editor-input" value={draft} disabled={isSaving}
        onChange={event => setDraft(event.target.value)} data-initial-focus
        aria-invalid={draft.length > 2000 || undefined} aria-describedby={`${inputId}-count`}
        onKeyDown={event => {
          if ((event.metaKey || event.ctrlKey) && event.key === 'Enter' && !event.nativeEvent.isComposing) {
            event.preventDefault(); void save();
          }
        }} />
      <p id={`${inputId}-count`} className={`message-editor-count${draft.length > 2000 ? ' over-limit' : ''}`}>{draft.length} / 2000</p>
      {(sessionExpired || errorMessage) && <p className="message-editor-error" role="alert">{sessionExpired ? t('message_edit.session_expired') : errorMessage}</p>}
    </Modal>
    {confirmDiscard && <Modal title={t('message_edit.discard_title')} message=""
      confirmText={t('message_edit.discard')} cancelText={t('message_edit.keep')} destructive
      onConfirm={onCancel} onCancel={() => setConfirmDiscard(false)} />}
  </>;
};
