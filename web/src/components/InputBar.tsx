import React, { useState, useRef } from 'react';
import { api } from '../api/client';
import { ArrowUpCircle, ImagePlus } from 'lucide-react';
import { useTranslation } from 'react-i18next';

interface Props {
  onSent: () => void;
}

export const InputBar: React.FC<Props> = ({ onSent }) => {
  const [text, setText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { t } = useTranslation();

  const handleSendText = async () => {
    const trimmed = text.trim();
    if (!trimmed || isSending) return;
    
    setIsSending(true);
    try {
      await api.sendTextMessage(trimmed);
      setText('');
      onSent();
    } catch (e) {
      console.error(e);
      alert(t('sync.error_context.send', 'Send failed'));
    }
    setIsSending(false);
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsSending(true);
    try {
      await api.sendImageMessage(file);
      onSent();
    } catch (err) {
      console.error(err);
      alert(t('sync.error_context.send_image', 'Image send failed'));
    }
    
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
    }
    setIsSending(false);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSendText();
    }
  };

  return (
    <div className="input-bar">
      <div className="photo-upload">
        <ImagePlus size={24} />
        <input 
          type="file" 
          accept="image/*" 
          onChange={handleFileChange} 
          ref={fileInputRef} 
          disabled={isSending}
        />
      </div>
      
      <textarea
        placeholder={t('message_list.input_placeholder', 'Capture your thoughts...')}
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={handleKeyDown}
        disabled={isSending}
        rows={1}
      />
      
      <button 
        onClick={handleSendText} 
        disabled={!text.trim() || isSending}
      >
        <ArrowUpCircle size={30} />
      </button>
    </div>
  );
};
