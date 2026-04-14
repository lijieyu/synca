import React, { useEffect, useState, useRef } from 'react';
import { api, type SyncaMessage } from '../api/client';
import { MessageBubble } from './MessageBubble';
import { InputBar } from './InputBar';
import { useAuth } from '../contexts/AuthContext';
import { LogOut, RefreshCcw, Trash2, Lightbulb } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Toast } from './Toast';
import { Modal } from './Modal';

export const MessageListView: React.FC = () => {
  const [messages, setMessages] = useState<SyncaMessage[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { logout, isAdmin, email, plan, accessStatus, refreshAccessStatus } = useAuth();
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
      
      // Refresh badge information in background
      refreshAccessStatus();
    } catch (err) {
      console.error(err);
    } finally {
      setIsLoading(false);
    }
  };

  const getPlanInfo = () => {
    if (!plan || !accessStatus) return null;
    
    let label = plan;
    let color = 'rgba(142, 142, 147, 0.15)';
    let isUnlimited = false;

    if (plan === 'unlimited') {
      label = t('access.status_unlimited_compact');
      color = 'rgba(125, 77, 255, 0.15)';
      isUnlimited = true;
    } else if (plan === 'free') {
      label = t('access.status_free_compact', { used: accessStatus.todayUsed, limit: accessStatus.todayLimit ?? 20 });
    }

    return (
      <span className="admin-tag" style={{ 
        background: color, 
        marginLeft: '6px', 
        fontSize: '10px',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '4px'
      }}>
        {label}
        {isUnlimited && <span style={{ fontSize: '12px', lineHeight: 1 }}>∞</span>}
      </span>
    );
  };

  const handleRefresh = async () => {
    await fetchMessages(false);
    setToastMsg(t('message_list.sync_success', 'Synced'));
    setShowToast(true);
  };

  const handleClearAll = async () => {
    setShowClearAllModal(false);
    try {
      await api.deleteCompletedMessages();
      await fetchMessages(false);
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
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <img src="/logo.png" alt="Logo" style={{ width: '32px', height: '32px', borderRadius: '8px' }} />
          <h1 className="header-title">{t('app.name', 'Synca')}</h1>
        </div>
        <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
          {/* Action Group */}
          <div style={{ display: 'flex', gap: '4px' }}>
            {isAdmin && (
              <button className="header-btn" onClick={() => window.open('/admin', '_blank')} title="Admin Dashboard">
                <span style={{ fontSize: '12px', fontWeight: 500, color: 'var(--synca-purple)', padding: '0 4px' }}>Manage</span>
              </button>
            )}
            <button className="header-btn" onClick={handleRefresh} title={t('message_list.sync_success', 'Sync')}>
              <RefreshCcw size={18} />
            </button>
            <button 
              className="header-btn" 
              onClick={() => setShowClearAllModal(true)} 
              disabled={completed.length === 0}
              title={t('message_list.clear_all_confirm_title', 'Clear All')}
              style={{ opacity: completed.length === 0 ? 0.3 : 1 }}
            >
              <Trash2 size={18} />
            </button>
          </div>

          <div style={{ width: '1px', height: '20px', background: 'var(--border-color)', margin: '0 8px', opacity: 0.8 }}></div>

          {/* Account Group */}
          {email && (
            <div style={{ 
              display: 'flex', 
              alignItems: 'center', 
              gap: '12px',
              padding: '4px 8px 4px 14px',
              borderRadius: '20px',
              background: 'rgba(0,0,0,0.03)',
              border: '1px solid var(--border-color)',
              whiteSpace: 'nowrap'
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span style={{ fontSize: '12px', fontWeight: 500, opacity: 0.9 }}>{email}</span>
                {getPlanInfo()}
              </div>
              <button 
                className="header-btn" 
                onClick={() => setShowLogoutModal(true)} 
                title={t('message_list.logout', 'Sign Out')}
                style={{ width: '28px', height: '28px', minWidth: '28px', background: 'transparent', margin: 0 }}
              >
                <LogOut size={14} />
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="message-list" ref={listRef}>
        {isLoading && messages.length === 0 && <p style={{ textAlign: 'center', opacity: 0.5, marginTop: '20px' }}>{t('message_list.loading', 'Loading...')}</p>}
        
        {!isLoading && messages.length === 0 && (
          <div className="empty-state">
            <Lightbulb className="empty-state-icon" size={60} />
            <h2 className="empty-state-title">{t('app.name')}</h2>
            <p className="empty-state-slogan">{t('app.slogan')}</p>
          </div>
        )}

        {messages.length > 0 && (
          <>
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
          </>
        )}
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
