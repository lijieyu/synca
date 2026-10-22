import React, { useState, useRef, useCallback, useEffect } from 'react';
import { api, DailyLimitError, StorageError } from '../api/client';
import { ImagePlus, Paperclip } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Toast } from './Toast';
import { PlanDialog } from './PlanDialog';
import { useAuth } from '../contexts/AuthContext';

interface Props {
  onSent: () => void;
  categoryId?: string | null;
}

// SF Symbol: arrow.up.circle.fill equivalent as inline SVG
const SendIcon = ({ size = 30, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 30 30" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="15" cy="15" r="14" fill={color} />
    <path d="M15 22V9M15 9L10.5 13.5M15 9L19.5 13.5" stroke="var(--send-icon-arrow-color)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const InputBar: React.FC<Props> = ({ onSent, categoryId }) => {
  const { accessStatus } = useAuth();
  const uploadController = useRef<AbortController | null>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const [retryAttachment, setRetryAttachment] = useState<{ file: File; image: boolean; categoryId?: string | null } | null>(null);
  useEffect(() => () => uploadController.current?.abort(), []);
  const [text, setText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [toastMsg, setToastMsg] = useState('');
  const [showToast, setShowToast] = useState(false);
  const [showLimitModal, setShowLimitModal] = useState(false);
  const imageInputRef = useRef<HTMLInputElement>(null);
  const documentInputRef = useRef<HTMLInputElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const { t } = useTranslation();

  const supportedDocumentExtensions = '.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.txt,.md,.csv,.zip,image/*';
  const supportedDocumentExtensionSet = new Set(['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'csv', 'zip']);
  const maxDocumentSize = 200 * 1024 * 1024;
  useEffect(() => {
    // Focus when not sending (initial mount and after message sent)
    if (!isSending) {
      textareaRef.current?.focus();
    }
  }, [isSending]);

  const autoGrow = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 160) + 'px';
  }, []);

  const handleSendText = async () => {
    const trimmed = text.trim();
    if (!trimmed || isSending) return;
    
    setIsSending(true);
    try {
      await api.sendTextMessage(trimmed, categoryId);
      setText('');
      // Reset textarea height
      if (textareaRef.current) {
        textareaRef.current.style.height = 'auto';
      }
      onSent();
    } catch (e) {
      console.error(e);
      if (e instanceof DailyLimitError) {
        setShowLimitModal(true);
      } else {
        setToastMsg(t('storage.text_send_failed'));
        setShowToast(true);
      }
    }
    setIsSending(false);
  };

  const sendAttachment = async (file: File, image: boolean, targetCategoryId = categoryId) => {
    if (isSending) return;
    if (!image && !accessStatus?.isUnlimited) { setRetryAttachment({ file, image, categoryId: targetCategoryId ?? null }); setShowLimitModal(true); return; }
    if (!image && !supportedDocumentExtensionSet.has(file.name.split('.').pop()?.toLowerCase() ?? '')) {
      setToastMsg(t('message_file.error_unsupported')); setShowToast(true); return;
    }
    if (file.size > (image ? 50 * 1024 * 1024 : maxDocumentSize)) {
      setToastMsg(t(image ? 'storage.image_too_large' : 'message_file.error_too_large')); setShowToast(true); return;
    }
    const controller = new AbortController();
    uploadController.current = controller;
    setRetryAttachment(null);
    setProgress(0);
    setIsSending(true);
    try {
      const options = { signal: controller.signal, onProgress: setProgress };
      if (image) await api.sendImageMessage(file, targetCategoryId, options);
      else await api.sendFileMessage(file, targetCategoryId, options);
      onSent();
    } catch (error) {
      setRetryAttachment({ file, image, categoryId: targetCategoryId ?? null });
      if (error instanceof DailyLimitError || (error instanceof StorageError && error.code === 'file_upload_requires_paid')) setShowLimitModal(true);
      else if (!(error instanceof DOMException && error.name === 'AbortError')) {
        setToastMsg(t(error instanceof StorageError && error.code === 'storage_limit_reached' ? 'storage.full' : image ? 'storage.image_send_failed' : 'storage.file_send_failed'));
        setShowToast(true);
      }
    } finally {
      uploadController.current = null;
      setProgress(null);
      setIsSending(false);
      if (imageInputRef.current) imageInputRef.current.value = '';
      if (documentInputRef.current) documentInputRef.current.value = '';
    }
  };
  const sendImage = (file: File) => sendAttachment(file, true);
  const sendFile = (file: File) => sendAttachment(file, false);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (file) {
      await sendImage(file);
    }
  };

  const handleDocumentChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (file) {
      if (file.type.startsWith('image/')) {
        await sendImage(file);
      } else {
        await sendFile(file);
      }
    }
  };

  const handlePaste = async (e: React.ClipboardEvent) => {
    const items = e.clipboardData.items;
    for (let i = 0; i < items.length; i++) {
      if (items[i].type.indexOf('image') !== -1) {
        const file = items[i].getAsFile();
        if (file) {
          e.preventDefault();
          await sendImage(file);
          return;
        }
      }
    }

    const files = Array.from(e.clipboardData.files);
    const supportedFile = files.find((file) => !file.type.startsWith('image/'));
    if (supportedFile) {
      e.preventDefault();
      await sendFile(supportedFile);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    // Do not send while Enter is confirming Chinese/Japanese input (Safari also uses keyCode 229).
    if (e.nativeEvent.isComposing || e.nativeEvent.keyCode === 229) return;
    // Enter alone (no meta, no shift) = send
    if (e.key === 'Enter' && !e.shiftKey && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      handleSendText();
    } 
    // Cmd+Enter = explicit newline
    else if (e.key === 'Enter' && e.metaKey) {
      e.preventDefault();
      const el = textareaRef.current;
      if (!el) return;
      
      const start = el.selectionStart;
      const end = el.selectionEnd;
      const value = el.value;
      
      // Update text state with newline at cursor
      const newText = value.substring(0, start) + "\n" + value.substring(end);
      setText(newText);
      
      // We need to set selection after React re-renders, but for a quick fix 
      // we can rely on the onChange and autoGrow.
      // However, to be precise:
      setTimeout(() => {
        el.selectionStart = el.selectionEnd = start + 1;
        autoGrow();
        // Only scroll if we have actually hit the max-height limit (160px)
        if (el.scrollHeight > 160) {
          el.scrollTop = el.scrollHeight;
        }
      }, 0);
    }
  };

  return (
    <>
      <div className="input-bar">
        <div className="input-shell">
          <div className="photo-upload">
            <ImagePlus size={24} />
            <input
              type="file"
              accept="image/*"
              aria-label={t('storage.choose_image')}
              onChange={handleFileChange}
              ref={imageInputRef}
              disabled={isSending}
            />
          </div>

          <div className="photo-upload file-upload">
            <Paperclip size={22} />
            <input
              type="file"
              accept={supportedDocumentExtensions}
              aria-label={t('storage.choose_file')}
              onChange={handleDocumentChange}
              ref={documentInputRef}
              disabled={isSending}
            />
          </div>

          <textarea
            ref={textareaRef}
            className={isSending ? 'sending' : ''}
            placeholder={isSending ? t('message_list.sending_placeholder', 'Sending...') : t('message_list.input_placeholder', 'Capture your thoughts...')}
            value={text}
            onChange={(e) => { setText(e.target.value); autoGrow(); }}
            onKeyDown={handleKeyDown}
            onPaste={handlePaste}
            disabled={isSending}
            aria-label={t('message_list.input_placeholder', 'Capture your thoughts...')}
            rows={1}
          />

          <button
            className="send-btn"
            aria-label={t('common.send')}
            onClick={handleSendText}
            disabled={!text.trim() || isSending}
          >
            <SendIcon size={30} color={text.trim() && !isSending ? 'var(--synca-purple)' : 'var(--text-secondary)'} />
          </button>
        </div>
      </div>

      {(progress !== null || (retryAttachment && !isSending)) && <div className="transfer-status" aria-live="polite">
        {progress !== null && <div className="transfer-progress">
          <progress value={progress} max={1} aria-label={t('storage.uploading')} />
          <span>{Math.round(progress * 100)}%</span>
          <button onClick={() => uploadController.current?.abort()}>{t('common.cancel')}</button>
        </div>}
        {retryAttachment && !isSending && <div className="transfer-progress">
          <span>{t('storage.retry_hint')}</span>
          <button onClick={() => void sendAttachment(retryAttachment.file, retryAttachment.image, retryAttachment.categoryId)}>{t('storage.retry')}</button>
          <button onClick={() => setRetryAttachment(null)}>{t('common.cancel')}</button>
        </div>}
      </div>}
      <Toast variant="error" duration={6000} message={toastMsg} visible={showToast} onClose={() => setShowToast(false)} />

      {showLimitModal && <PlanDialog onClose={() => setShowLimitModal(false)} />}

    </>
  );
};
