import React, { useEffect, useState, useRef } from 'react';
import { SyncaMessage, api } from '../api/client';
import { MessageBubble } from './MessageBubble';
import { InputBar } from './InputBar';
import { useAuth } from '../contexts/AuthContext';
import { LogOut, RefreshCcw } from 'lucide-react';

export const MessageListView: React.FC = () => {
  const [messages, setMessages] = useState<SyncaMessage[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { logout } = useAuth();
  const listRef = useRef<HTMLDivElement>(null);

  const fetchMessages = async (scrollToBottom = true) => {
    try {
      const res = await api.listMessages();
      
      // Sort logic identical to iOS app
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

  useEffect(() => {
    fetchMessages();
    
    // Polling every 10s
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
        <h1 className="header-title">Synca Web</h1>
        <div style={{ display: 'flex', gap: '16px', alignItems: 'center' }}>
          <button className="logout-btn" onClick={() => fetchMessages(false)} style={{ color: 'var(--text-main)' }}>
            <RefreshCcw size={18} />
          </button>
          <button className="logout-btn" onClick={logout}>
            <LogOut size={18} />
          </button>
        </div>
      </div>

      <div className="message-list" ref={listRef}>
        {isLoading && <p style={{ textAlign: 'center', opacity: 0.5 }}>Loading...</p>}
        
        {completed.map(msg => (
          <MessageBubble key={msg.id} message={msg} onUpdate={() => fetchMessages(false)} />
        ))}

        {uncompleted.length > 0 && (
          <div style={{ marginTop: '8px', marginBottom: '4px' }}>
            <span style={{ fontSize: '12px', fontWeight: 'bold', color: 'var(--text-secondary)', background: 'var(--border-color)', padding: '2px 8px', borderRadius: '4px' }}>
              Pending
            </span>
          </div>
        )}

        {uncompleted.map(msg => (
          <MessageBubble key={msg.id} message={msg} onUpdate={() => fetchMessages(false)} />
        ))}
      </div>

      <InputBar onSent={() => fetchMessages(true)} />
    </div>
  );
};
