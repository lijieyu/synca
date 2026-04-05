import React, { useState } from 'react';
import { api, type SyncaMessage } from '../api/client';
import { Trash2 } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Modal } from './Modal';

interface Props {
  message: SyncaMessage;
  onUpdate: () => void;
}

const CheckCircleFill = ({ size = 20, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="12" cy="12" r="10" fill={color} />
    <path d="M8 12L11 15L16 9" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const MessageBubble: React.FC<Props> = ({ message, onUpdate }) => {
  const [isProcessing, setIsProcessing] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const { t } = useTranslation();

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

  return (
    <>
      <div className={`message-bubble ${message.isCleared ? 'cleared' : ''}`}>
        {message.type === 'text' && (
          <div className="message-content">{message.textContent}</div>
        )}
        
        {message.type === 'image' && message.imageUrl && (
          <img 
            src={message.imageUrl} 
            alt="Shared content" 
            className="message-image" 
          />
        )}

        <div className="message-header">
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span>{formatTime(message.createdAt)}</span>
            <span>·</span>
            <span>{message.sourceDevice}</span>
          </div>
          
          <div className="actions">
            <button className="action-btn" onClick={() => setShowDeleteModal(true)} disabled={isProcessing} title={t('common.delete', 'Delete')}>
              <Trash2 size={16} />
            </button>
            <button 
              className={`action-btn ${message.isCleared ? 'cleared-icon' : ''}`} 
              onClick={handleClear} 
              disabled={message.isCleared || isProcessing}
            >
              <CheckCircleFill size={18} color={message.isCleared ? 'var(--synca-mint)' : 'var(--text-secondary)'} />
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
