import React, { useState, useRef, useCallback, useEffect } from 'react';
import { api } from '../api/client';
import { ImagePlus } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Toast } from './Toast';

interface Props {
  onSent: () => void;
}

// SF Symbol: arrow.up.circle.fill equivalent as inline SVG
const SendIcon = ({ size = 30, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 30 30" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="15" cy="15" r="14" fill={color} />
    <path d="M15 22V9M15 9L10.5 13.5M15 9L19.5 13.5" stroke="var(--send-icon-arrow-color)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
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

  const sendImage = async (file: File) => {
    if (isSending) return;
    setIsSending(true);
    try {
      await api.sendImageMessage(file);
      onSent();
    } catch (err) {
      console.error(err);
      setToastMsg(t('sync.error_context.send_image', 'Image send failed'));
      setShowToast(true);
    }
    setIsSending(false);
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
    }
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      await sendImage(file);
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
          break; // Send first image found
        }
      }
    }
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
          className={isSending ? 'sending' : ''}
          placeholder={isSending ? t('message_list.sending_placeholder', 'Sending...') : t('message_list.input_placeholder', 'Capture your thoughts...')}
          value={text}
          onChange={(e) => { setText(e.target.value); autoGrow(); }}
          onKeyDown={handleKeyDown}
          onPaste={handlePaste}
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
