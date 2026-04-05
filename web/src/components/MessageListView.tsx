import React, { useEffect, useState, useRef } from 'react';
import { api, type SyncaMessage } from '../api/client';
import { MessageBubble } from './MessageBubble';
import { InputBar } from './InputBar';
import { useAuth } from '../contexts/AuthContext';
import { LogOut, RefreshCcw, Trash2 } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Toast } from './Toast';
import { Modal } from './Modal';

export const MessageListView: React.FC = () => {
  const [messages, setMessages] = useState<SyncaMessage[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { logout } = useAuth();
  const { t } = useTranslation();
  const listRef = useRef<HTMLDivElement>(null);
  
  const [toastMsg, setToastMsg] = useState('');
  const [showToast, setShowToast] = useState(false);
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showClearAllModal, setShowClearAllModal] = useState(false);

  const fetchMessages = async (scrollToBottom = true) => {
    try {
      const res = await api.listMessages();
      
      const sorted = res.messages.sort((m1, m2) => {
        if (m1.isCleared !== m2.isCleared) {
          return m1.isCleared ? 1 : -1;
        }
        if (m1.isCleared) {
          return new Date(m1.updatedAt).getTime() - new Date(m2.updatedAt).getTime();
        }
        return new Date(m1.createdAt).getTime() - new Date(m2.createdAt).getTime();
      });

      setMessages(sorted);
      if (scrollToBottom) {
        setTimeout(() => {
          if (listRef.current) {
            listRef.current.scrollTop = listRef.current.scrollHeight;
          }
        }, 100);
      }
    } catch (err) {
      console.error(err);
    } finally {
      setIsLoading(false);
    }
  };

  const handleRefresh = async () => {
    await fetchMessages(false);
    setToastMsg(t('message_list.sync_success', 'Synced'));
    setShowToast(true);
  };

  const handleClearAll = async () => {
    setShowClearAllModal(false);
    try {
      await api.clearAllMessages();
      await fetchMessages(false);
      setToastMsg(t('message_list.sync_success', 'Synced'));
      setShowToast(true);
    } catch (err) {
      console.error(err);
    }
  };

  useEffect(() => {
    fetchMessages();
    
    const timer = setInterval(() => {
      fetchMessages(false);
    }, 10000);
    return () => clearInterval(timer);
  }, []);

  const completed = messages.filter(m => m.isCleared);
  const uncompleted = messages.filter(m => !m.isCleared);

  return (
    <div className="app-container">
      <div className="header">
        <h1 className="header-title">{t('app.name', 'Synca')}</h1>
        <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
          <button className="header-btn" onClick={handleRefresh} title={t('message_list.sync_success', 'Sync')}>
            <RefreshCcw size={18} />
          </button>
          {completed.length > 0 && (
            <button className="header-btn" onClick={() => setShowClearAllModal(true)} title={t('message_list.clear_all_confirm_title', 'Clear All')}>
              <Trash2 size={18} />
            </button>
          )}
          <button className="header-btn" onClick={() => setShowLogoutModal(true)} title={t('message_list.logout', 'Sign Out')}>
            <LogOut size={18} />
          </button>
        </div>
      </div>

      <div className="message-list" ref={listRef}>
        {isLoading && <p style={{ textAlign: 'center', opacity: 0.5 }}>{t('message_list.loading', 'Loading...')}</p>}
        
        {completed.map(msg => (
          <MessageBubble key={msg.id} message={msg} onUpdate={() => fetchMessages(false)} />
        ))}

        {uncompleted.length > 0 && (
          <div style={{ marginTop: '8px', marginBottom: '4px' }}>
            <span style={{ fontSize: '12px', fontWeight: 'bold', color: 'var(--text-secondary)', background: 'var(--border-color)', padding: '2px 8px', borderRadius: '4px' }}>
              {t('message_list.todo_section', 'Inbox')}
            </span>
          </div>
        )}

        {uncompleted.map(msg => (
          <MessageBubble key={msg.id} message={msg} onUpdate={() => fetchMessages(false)} />
        ))}
      </div>

      <InputBar onSent={() => fetchMessages(true)} />

      <Toast message={toastMsg} visible={showToast} onClose={() => setShowToast(false)} />

      {showLogoutModal && (
        <Modal
          title={t('message_list.logout_confirm_title', 'Confirm Sign Out')}
          message={t('message_list.logout_confirm_message', 'You will need to sign in again')}
          confirmText={t('message_list.sign_out', 'Sign Out')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={logout}
          onCancel={() => setShowLogoutModal(false)}
          destructive
        />
      )}

      {showClearAllModal && (
        <Modal
          title={t('message_list.clear_all_confirm_title', 'Confirm Delete')}
          message={t('message_list.clear_all_confirm_message', 'This will delete all completed to-dos')}
          confirmText={t('common.delete', 'Delete')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={handleClearAll}
          onCancel={() => setShowClearAllModal(false)}
          destructive
        />
      )}
    </div>
  );
};
