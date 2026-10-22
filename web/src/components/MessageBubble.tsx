import React, { useMemo, useState } from 'react';
import { api, StorageError, type MessageCategory, type SyncaMessage } from '../api/client';
import { Download, FileArchive, FileSpreadsheet, FileText, FileType2, Presentation, Trash2 } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Modal } from './Modal';
import { Toast } from './Toast';
import { AuthImage } from './AuthImage';

interface Props {
  message: SyncaMessage;
  categories: MessageCategory[];
  onUpdate: () => void;
}

const CheckCircleFill = ({ size = 20, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="12" cy="12" r="10" fill={color} />
    <path d="M8 12L11 15L16 9" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const CheckCircleOutline = ({ size = 20, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="12" cy="12" r="10" stroke={color} strokeWidth="1.8" />
    <path d="M8 12L11 15L16 9" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const MessageBubble: React.FC<Props> = ({ message, categories, onUpdate }) => {
  const [actionError, setActionError] = useState('');
  const [attachmentExpired, setAttachmentExpired] = useState(false);
  const expired = attachmentExpired || message.attachmentExpired || Boolean(message.attachmentExpiresAt && Date.parse(message.attachmentExpiresAt) <= Date.now());
  const [isProcessing, setIsProcessing] = useState(false);
  const [fileAction, setFileAction] = useState<'open' | 'download' | null>(null);
  const [isImageOpening, setIsImageOpening] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const { t } = useTranslation();
  const reportError = (error: unknown) => {
    if (error instanceof DOMException && error.name === 'AbortError') return;
    const expired = error instanceof StorageError && error.code === 'attachment_expired';
    if (expired) setAttachmentExpired(true);
    setActionError(t(expired ? 'storage.expired' : 'storage.action_failed'));
  };
  const openPreview = (objectUrl: string, previewWindow: Window | null) => {
    if (previewWindow) previewWindow.location.href = objectUrl;
    else window.open(objectUrl, '_blank', 'noopener,noreferrer');
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 60_000);
  };
  const fileExtension = useMemo(() => {
    if (!message.fileName) return '';
    const ext = message.fileName.split('.').pop();
    return ext ? ext.toUpperCase() : '';
  }, [message.fileName]);

  const fileIcon = useMemo(() => {
    const ext = fileExtension.toLowerCase();
    if (ext === 'pdf' || ext === 'txt' || ext === 'md') return <FileText size={22} />;
    if (ext === 'xls' || ext === 'xlsx' || ext === 'csv') return <FileSpreadsheet size={22} />;
    if (ext === 'ppt' || ext === 'pptx') return <Presentation size={22} />;
    if (ext === 'zip') return <FileArchive size={22} />;
    return <FileType2 size={22} />;
  }, [fileExtension]);

  const linkify = (text: string): React.ReactNode[] => {
    const urlPattern = /(https?:\/\/[^\s<>"{}|\\^`[\]，。！？；：、]+[^\s<>"{}|\\^`[\],.)!?;:，。！？；：、])/g;
    const parts = text.split(urlPattern);
    const isUrl = /^https?:\/\//;
    return parts.map((part, i) =>
      isUrl.test(part) ? (
        <a
          key={i}
          href={part}
          target="_blank"
          rel="noopener noreferrer"
          className="message-link"
        >
          {part}
        </a>
      ) : (
        <React.Fragment key={i}>{part}</React.Fragment>
      )
    );
  };

  const formatTime = (isoString: string) => {
    const d = new Date(isoString);
    return isNaN(d.getTime()) ? '' : d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  const handleClear = async () => {
    if (message.isCleared || isProcessing) return;
    setIsProcessing(true);
    try {
      await api.clearMessage(message.id);
      onUpdate();
    } catch (e) {
      reportError(e);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleDelete = async () => {
    setShowDeleteModal(false);
    setIsProcessing(true);
    try {
      await api.deleteMessage(message.id);
      onUpdate();
    } catch (e) {
      reportError(e);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleFileOpen = async () => {
    if (expired || !message.fileUrl || isProcessing) return;
    const previewWindow = window.open('', '_blank');
    if (previewWindow) {
      previewWindow.opener = null;
    }
    setIsProcessing(true);
    setFileAction('open');
    try {
      const objectUrl = await api.openProtectedFile(message.fileUrl, message.attachmentExpiresAt);
      openPreview(objectUrl, previewWindow);
    } catch (e) {
      previewWindow?.close();
      reportError(e);
    } finally {
      setFileAction(null);
      setIsProcessing(false);
    }
  };

  const handleFileDownload = async (event?: React.MouseEvent) => {
    event?.stopPropagation();
    if (expired || !message.fileUrl || isProcessing) return;
    setIsProcessing(true);
    setFileAction('download');
    try {
      await api.downloadProtectedFile(message.fileUrl, message.fileName, message.attachmentExpiresAt);
    } catch (e) {
      reportError(e);
    } finally {
      setFileAction(null);
      setIsProcessing(false);
    }
  };

  const handleImageOpen = async () => {
    if (expired || !message.imageUrl || isProcessing || isImageOpening) return;
    const previewWindow = window.open('', '_blank');
    if (previewWindow) {
      previewWindow.opener = null;
    }
    setIsImageOpening(true);
    try {
      const objectUrl = await api.openProtectedFile(message.imageUrl, message.attachmentExpiresAt);
      openPreview(objectUrl, previewWindow);
    } catch (e) {
      previewWindow?.close();
      reportError(e);
    } finally {
      setIsImageOpening(false);
    }
  };

  const handleImageKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      void handleImageOpen();
    }
  };

  const handleCategoryChange = async (categoryId: string) => {
    if (isProcessing || categoryId === message.categoryId) return;
    setIsProcessing(true);
    try {
      await api.updateMessageCategoryAssignment(message.id, categoryId);
      onUpdate();
    } catch (e) {
      reportError(e);
    } finally {
      setIsProcessing(false);
    }
  };

  const formatFileSize = (bytes: number | null) => {
    if (!bytes || bytes <= 0) return '';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <>
      <div className={`message-bubble ${message.isCleared ? 'cleared' : ''}`}>
        {message.type !== 'text' && expired && <p className="attachment-expiry">{t('storage.expired')}</p>}
        {message.type !== 'text' && !expired && message.attachmentExpiresAt && <p className="attachment-expiry">{t('storage.expires')}: {new Date(message.attachmentExpiresAt).toLocaleString()}</p>}
        {message.type === 'text' && (
          <div className="message-content">{linkify(message.textContent ?? '')}</div>
        )}
        
        {!expired && message.type === 'image' && message.imageUrl && (
          <AuthImage
            url={message.imageUrl}
            expiresAt={message.attachmentExpiresAt}
            alt={t('storage.shared_image')}
            className={`message-image ${isImageOpening ? 'opening' : ''}`}
            onClick={() => void handleImageOpen()}
            onKeyDown={handleImageKeyDown}
            role="button"
            tabIndex={0}
            aria-label={t('image_preview.open', 'Open image')}
          />
        )}

        {!expired && message.type === 'file' && (
          <button className="file-card" onClick={handleFileOpen} disabled={isProcessing}>
            <div className="file-card-icon">{fileIcon}</div>
            <div className="file-card-meta">
              <div className="file-card-name">{message.fileName ?? 'Attachment'}</div>
              <div className="file-card-detail">
                {fileExtension && <span>{fileExtension}</span>}
                {message.fileSize != null && <span>{formatFileSize(message.fileSize)}</span>}
                {fileAction === 'open' && <span>{t('common.opening', 'Opening...')}</span>}
              </div>
            </div>
          </button>
        )}

        <div className="message-header">
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span>{formatTime(message.createdAt)}</span>
            <span>·</span>
            <span>{message.sourceDevice}</span>
            {message.categoryName && (
              <>
                <span>·</span>
                <div style={{ display: 'inline-flex', alignItems: 'center', gap: '2px', position: 'relative' }}>
                  <span>{
                    (() => {
                      const cat = categories.find(c => c.id === message.categoryId);
                      if (cat?.isDefault) return t('message_category.default_badge', '默认');
                      return message.categoryName;
                    })()
                  }</span>
                  <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" style={{ marginTop: '1px' }}><polyline points="6 9 12 15 18 9"></polyline></svg>
                  <select
                    style={{
                      position: 'absolute',
                      inset: 0,
                      opacity: 0,
                      cursor: 'pointer',
                      width: '100%',
                      height: '100%'
                    }}
                    value={message.categoryId ?? ''}
                    onChange={(e) => handleCategoryChange(e.target.value)}
                    disabled={isProcessing}
                    aria-label={t('storage.message_category')}
                  >
                    {categories.map((category) => (
                      <option key={category.id} value={category.id}>
                        {category.isDefault ? t('message_category.default_badge', '默认') : category.name}
                      </option>
                    ))}
                  </select>
                </div>
              </>
            )}
          </div>
          
          <div className="actions">
            {!expired && message.type === 'file' && (
              <button className="action-btn" onClick={handleFileDownload} disabled={isProcessing} title={t('common.save', 'Save')}>
                {fileAction === 'download' ? <span className="action-spinner" aria-hidden="true" /> : <Download size={16} />}
              </button>
            )}
            <button className="action-btn" onClick={() => setShowDeleteModal(true)} disabled={isProcessing} title={t('common.delete', 'Delete')}>
              <Trash2 size={16} />
            </button>
            <button 
              className={`action-btn ${message.isCleared ? 'cleared-icon' : ''}`} 
              aria-label={t(message.isCleared ? 'storage.completed' : 'storage.mark_complete')}
              onClick={handleClear} 
              disabled={message.isCleared || isProcessing}
            >
              {message.isCleared ? (
                <CheckCircleFill size={18} color="var(--cleared-icon-color)" />
              ) : (
                <CheckCircleOutline size={18} color="var(--text-secondary)" />
              )}
            </button>
          </div>
        </div>
      </div>

      <Toast variant="error" duration={6000} message={actionError} visible={Boolean(actionError)} onClose={() => setActionError('')} />
      {showDeleteModal && (
        <Modal
          title={t('message_bubble.delete_confirm_title', 'Confirm Delete')}
          message={t('message_bubble.delete_confirm_message', 'This will permanently delete this record from the cloud and cannot be undone.').replace('%@', '')}
          confirmText={t('common.delete', 'Delete')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={handleDelete}
          onCancel={() => setShowDeleteModal(false)}
          destructive
        />
      )}
    </>
  );
};
