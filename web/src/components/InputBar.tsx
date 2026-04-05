import React, { useState, useRef, useCallback } from 'react';
import { api } from '../api/client';
import { ImagePlus } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Toast } from './Toast';

interface Props {
  onSent: () => void;
}

// SF Symbol: arrow.up.circle.fill equivalent as inline SVG
const SendIcon = ({ size = 30, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={color} xmlns="http://www.w3.org/2000/svg">
    <circle cx="12" cy="12" r="12" />
    <path d="M12 7L12 17" stroke="white" strokeWidth="2" strokeLinecap="round" />
    <path d="M8 11L12 7L16 11" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const InputBar: React.FC<Props> = ({ onSent }) => {
  const [text, setText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [toastMsg, setToastMsg] = useState('');
  const [showToast, setShowToast] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const { t } = useTranslation();

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
      await api.sendTextMessage(trimmed);
      setText('');
      // Reset textarea height
      if (textareaRef.current) {
        textareaRef.current.style.height = 'auto';
      }
      onSent();
    } catch (e) {
      console.error(e);
      setToastMsg(t('sync.error_context.send', 'Send failed'));
      setShowToast(true);
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
      setToastMsg(t('sync.error_context.send_image', 'Image send failed'));
      setShowToast(true);
    }
    
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
    }
    setIsSending(false);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
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
          ref={textareaRef}
          placeholder={t('message_list.input_placeholder', 'Capture your thoughts...')}
          value={text}
          onChange={(e) => { setText(e.target.value); autoGrow(); }}
          onKeyDown={handleKeyDown}
          disabled={isSending}
          rows={1}
        />
        
        <button 
          className="send-btn"
          onClick={handleSendText} 
          disabled={!text.trim() || isSending}
        >
          <SendIcon size={30} color={text.trim() && !isSending ? 'var(--synca-purple)' : 'var(--text-secondary)'} />
        </button>
      </div>

      <Toast message={toastMsg} visible={showToast} onClose={() => setShowToast(false)} />
    </>
  );
};
