import React, { useMemo, useState } from 'react';
import { api, type MessageCategory, type SyncaMessage } from '../api/client';
import { Download, FileArchive, FileSpreadsheet, FileText, FileType2, Presentation, Trash2 } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Modal } from './Modal';
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
  const [isProcessing, setIsProcessing] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const { t } = useTranslation();
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
    const urlPattern = /(https?:\/\/[^\s<>"{}|\\^`[\]]+[^\s<>"{}|\\^`[\],.)!?;:，。！？；：])/g;
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
      console.error(e);
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
      console.error(e);
      setIsProcessing(false);
    }
  };

  const handleFileDownload = async () => {
    if (!message.fileUrl || isProcessing) return;
    setIsProcessing(true);
    try {
      await api.downloadProtectedFile(message.fileUrl, message.fileName);
    } catch (e) {
      console.error(e);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleCategoryChange = async (categoryId: string) => {
    if (isProcessing || categoryId === message.categoryId) return;
    setIsProcessing(true);
    try {
      await api.updateMessageCategoryAssignment(message.id, categoryId);
      onUpdate();
    } catch (e) {
      console.error(e);
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
        {message.type === 'text' && (
          <div className="message-content">{linkify(message.textContent ?? '')}</div>
        )}
        
        {message.type === 'image' && message.imageUrl && (
          <AuthImage 
            url={message.imageUrl} 
            alt="Shared content" 
            className="message-image" 
          />
        )}

        {message.type === 'file' && (
          <button className="file-card" onClick={handleFileDownload} disabled={isProcessing}>
            <div className="file-card-icon">{fileIcon}</div>
            <div className="file-card-meta">
              <div className="file-card-name">{message.fileName ?? 'Attachment'}</div>
              <div className="file-card-detail">
                {fileExtension && <span>{fileExtension}</span>}
                {message.fileSize != null && <span>{formatFileSize(message.fileSize)}</span>}
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
                <select
                  className={`message-category-pill color-${message.categoryColor ?? 'slate'}`}
                  value={message.categoryId ?? ''}
                  onChange={(e) => handleCategoryChange(e.target.value)}
                  disabled={isProcessing}
                  aria-label="Message category"
                >
                  {categories.map((category) => (
                    <option key={category.id} value={category.id}>
                      {category.name}
                    </option>
                  ))}
                </select>
              </>
            )}
          </div>
          
          <div className="actions">
            {message.type === 'file' && (
              <button className="action-btn" onClick={handleFileDownload} disabled={isProcessing} title={t('common.save', 'Save')}>
                <Download size={16} />
              </button>
            )}
            <button className="action-btn" onClick={() => setShowDeleteModal(true)} disabled={isProcessing} title={t('common.delete', 'Delete')}>
              <Trash2 size={16} />
            </button>
            <button 
              className={`action-btn ${message.isCleared ? 'cleared-icon' : ''}`} 
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
