import React, { useState } from 'react';
import { api, type SyncaMessage } from '../api/client';
import { CircleCheck, Trash2 } from 'lucide-react';

interface Props {
  message: SyncaMessage;
  onUpdate: () => void;
}

export const MessageBubble: React.FC<Props> = ({ message, onUpdate }) => {
  const [isProcessing, setIsProcessing] = useState(false);

  // Time formatter
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
    if (isProcessing) return;
    if (!window.confirm('Delete this message?')) return;
    
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
    <div className={`message-bubble ${message.isCleared ? 'cleared' : ''}`}>
      {message.type === 'text' && (
        <div className="message-content">{message.textContent}</div>
      )}
      
      {message.type === 'image' && message.imagePath && (
        <img 
          src={message.imagePath} 
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
          <button className="action-btn" onClick={handleDelete} disabled={isProcessing}>
            <Trash2 size={16} />
          </button>
          <button 
            className={`action-btn ${message.isCleared ? 'cleared-icon' : ''}`} 
            onClick={handleClear} 
            disabled={message.isCleared || isProcessing}
          >
            <CircleCheck size={16} />
          </button>
        </div>
      </div>
    </div>
  );
};
