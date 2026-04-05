import React, { useState, useRef } from 'react';
import { api } from '../api/client';
import { ArrowUpCircle, ImagePlus } from 'lucide-react';

interface Props {
  onSent: () => void;
}

export const InputBar: React.FC<Props> = ({ onSent }) => {
  const [text, setText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

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
      alert('Failed to send text');
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
      alert('Failed to send image');
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
        placeholder="Type a message..."
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
