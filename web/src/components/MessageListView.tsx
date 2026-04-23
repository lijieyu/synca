import React, { useEffect, useMemo, useRef, useState } from 'react';
import { api, type MessageCategory, type MessageCategoryColor, type SyncaMessage } from '../api/client';
import { MessageBubble } from './MessageBubble';
import { InputBar } from './InputBar';
import { useAuth } from '../contexts/AuthContext';
import { Grid2x2, Lightbulb, LogOut, Plus, RefreshCcw, Rows3, Settings2, Trash2 } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Toast } from './Toast';
import { Modal } from './Modal';

const ALL_CATEGORY_ID = '__all__';
const CATEGORY_COLORS: MessageCategoryColor[] = ['slate', 'sky', 'mint', 'amber', 'coral', 'violet', 'rose', 'ocean'];
const COLOR_LABELS: Record<MessageCategoryColor, string> = {
  slate: 'Slate',
  sky: 'Sky',
  mint: 'Mint',
  amber: 'Amber',
  coral: 'Coral',
  violet: 'Violet',
  rose: 'Rose',
  ocean: 'Ocean',
};

const sortMessages = (items: SyncaMessage[]) =>
  [...items].sort((m1, m2) => {
    if (m1.isCleared !== m2.isCleared) {
      return m1.isCleared ? 1 : -1;
    }
    if (m1.isCleared) {
      return new Date(m1.updatedAt).getTime() - new Date(m2.updatedAt).getTime();
    }
    return new Date(m1.createdAt).getTime() - new Date(m2.createdAt).getTime();
  });

const categoryScopeStorageKey = (email: string | null) => `synca.selectedCategory.${email ?? 'guest'}`;
const defaultSendCategoryStorageKey = (email: string | null) => `synca.defaultSendCategory.${email ?? 'guest'}`;
const layoutStorageKey = (email: string | null) => `synca.messageLayout.${email ?? 'guest'}`;

interface CategoryColumnProps {
  category: MessageCategory;
  messages: SyncaMessage[];
  categories: MessageCategory[];
  isLoading: boolean;
  onRefresh: () => Promise<void>;
  onClearCompleted: () => Promise<void>;
  onSent: () => Promise<void>;
}

const CategoryColumn: React.FC<CategoryColumnProps> = ({
  category,
  messages,
  categories,
  isLoading,
  onRefresh,
  onClearCompleted,
  onSent,
}) => {
  const listRef = useRef<HTMLDivElement>(null);
  const { t } = useTranslation();

  useEffect(() => {
    if (!listRef.current) return;
    listRef.current.scrollTop = listRef.current.scrollHeight;
  }, [messages.length]);

  const completed = messages.filter((message) => message.isCleared);
  const pending = messages.filter((message) => !message.isCleared);

  return (
    <section className="category-column">
      <div className="category-column-header">
        <div className="category-column-title-row">
          <span className={`category-chip color-${category.color}`}>{category.name}</span>
          <div className="category-column-actions">
            <button className="header-btn" onClick={() => void onRefresh()} title={t('message_list.sync_success', 'Sync')}>
              <RefreshCcw size={16} />
            </button>
            <button
              className="header-btn"
              onClick={() => void onClearCompleted()}
              disabled={completed.length === 0}
              title={t('message_list.clear_all_confirm_title', 'Clear')}
              style={{ opacity: completed.length === 0 ? 0.35 : 1 }}
            >
              <Trash2 size={16} />
            </button>
          </div>
        </div>
      </div>

      <div className="category-column-list" ref={listRef}>
        {isLoading && messages.length === 0 && <p className="category-column-empty-hint">{t('message_list.loading', 'Loading...')}</p>}
        {!isLoading && messages.length === 0 && <p className="category-column-empty-hint">{t('message_list.input_placeholder', 'Capture your thoughts...')}</p>}

        {completed.map((message) => (
          <MessageBubble key={message.id} message={message} categories={categories} onUpdate={() => void onRefresh()} />
        ))}

        {pending.length > 0 && (
          <div className="column-section-label">
            <span>{t('message_list.todo_section', 'Inbox')}</span>
          </div>
        )}

        {pending.map((message) => (
          <MessageBubble key={message.id} message={message} categories={categories} onUpdate={() => void onRefresh()} />
        ))}
      </div>

      <div className="category-column-input">
        <InputBar categoryId={category.id} onSent={() => void onSent()} />
      </div>
    </section>
  );
};

export const MessageListView: React.FC = () => {
  const [messages, setMessages] = useState<SyncaMessage[]>([]);
  const [categories, setCategories] = useState<MessageCategory[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [selectedCategoryId, setSelectedCategoryId] = useState<string>(ALL_CATEGORY_ID);
  const [layoutMode, setLayoutMode] = useState<'single' | 'tiled'>('single');
  const [defaultSendCategoryId, setDefaultSendCategoryId] = useState<string | null>(null);
  const [showToast, setShowToast] = useState(false);
  const [toastMsg, setToastMsg] = useState('');
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showClearModal, setShowClearModal] = useState(false);
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [newCategoryName, setNewCategoryName] = useState('');
  const [newCategoryColor, setNewCategoryColor] = useState<MessageCategoryColor>('sky');
  const listRef = useRef<HTMLDivElement>(null);

  const { logout, isAdmin, email, plan, accessStatus, refreshAccessStatus } = useAuth();
  const { t } = useTranslation();

  const fetchData = async (scrollToBottom = false) => {
    try {
      const [messagesRes, categoriesRes] = await Promise.all([
        api.listMessages(),
        api.listMessageCategories(),
      ]);

      const sortedMessages = sortMessages(messagesRes.messages);
      setMessages(sortedMessages);
      setCategories(categoriesRes.categories);
      refreshAccessStatus();

      const defaultCategory = categoriesRes.categories.find((category) => category.isDefault) ?? categoriesRes.categories[0];
      const storedSelected = localStorage.getItem(categoryScopeStorageKey(email)) ?? ALL_CATEGORY_ID;
      const storedDefaultSend = localStorage.getItem(defaultSendCategoryStorageKey(email));
      const storedLayout = localStorage.getItem(layoutStorageKey(email));

      setLayoutMode(storedLayout === 'tiled' ? 'tiled' : 'single');
      setSelectedCategoryId(
        storedSelected === ALL_CATEGORY_ID || categoriesRes.categories.some((category) => category.id === storedSelected)
          ? storedSelected
          : (defaultCategory?.id ?? ALL_CATEGORY_ID)
      );
      setDefaultSendCategoryId(
        storedDefaultSend && categoriesRes.categories.some((category) => category.id === storedDefaultSend)
          ? storedDefaultSend
          : (defaultCategory?.id ?? null)
      );

      if (scrollToBottom) {
        requestAnimationFrame(() => {
          if (listRef.current) {
            listRef.current.scrollTop = listRef.current.scrollHeight;
          }
        });
      }
    } catch (error) {
      console.error(error);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    void fetchData(true);
    const timer = setInterval(() => void fetchData(false), 10000);
    return () => clearInterval(timer);
  }, [email]);

  useEffect(() => {
    localStorage.setItem(categoryScopeStorageKey(email), selectedCategoryId);
  }, [email, selectedCategoryId]);

  useEffect(() => {
    localStorage.setItem(layoutStorageKey(email), layoutMode);
  }, [email, layoutMode]);

  useEffect(() => {
    if (defaultSendCategoryId) {
      localStorage.setItem(defaultSendCategoryStorageKey(email), defaultSendCategoryId);
    }
  }, [email, defaultSendCategoryId]);

  const defaultCategory = useMemo(
    () => categories.find((category) => category.isDefault) ?? categories[0] ?? null,
    [categories]
  );

  const effectiveDefaultSendCategoryId = defaultSendCategoryId ?? defaultCategory?.id ?? null;
  const selectedScopeIsAll = selectedCategoryId === ALL_CATEGORY_ID;
  const activeSendCategoryId = selectedScopeIsAll ? effectiveDefaultSendCategoryId : selectedCategoryId;
  const displayedSendCategoryId = selectedScopeIsAll ? effectiveDefaultSendCategoryId : activeSendCategoryId;

  const filteredMessages = useMemo(() => {
    if (selectedCategoryId === ALL_CATEGORY_ID) return messages;
    return messages.filter((message) => message.categoryId === selectedCategoryId);
  }, [messages, selectedCategoryId]);

  const tiledCategories = useMemo(() => categories, [categories]);
  const tiledColumnWidth = useMemo(() => {
    const count = Math.max(tiledCategories.length, 1);
    return `max(420px, calc((100vw - 32px - ${(count - 1) * 16}px) / ${count}))`;
  }, [tiledCategories.length]);

  const handleRefresh = async () => {
    await fetchData(false);
    setToastMsg(t('message_list.sync_success', 'Synced'));
    setShowToast(true);
  };

  const handleScopedClear = async (categoryId?: string | null) => {
    await api.deleteCompletedMessages(categoryId ?? null);
    await fetchData(false);
  };

  const handleCreateCategory = async () => {
    const trimmedName = newCategoryName.trim();
    if (!trimmedName) return;
    try {
      await api.createMessageCategory(trimmedName, newCategoryColor);
      setNewCategoryName('');
      setNewCategoryColor('sky');
      await fetchData(false);
    } catch (error) {
      console.error(error);
    }
  };

  const handleCategoryUpdate = async (category: MessageCategory, patch: Partial<Pick<MessageCategory, 'name' | 'color'>>) => {
    try {
      await api.updateMessageCategory(category.id, patch);
      await fetchData(false);
    } catch (error) {
      console.error(error);
    }
  };

  const handleCategoryDelete = async (categoryId: string) => {
    try {
      await api.deleteMessageCategory(categoryId);
      if (selectedCategoryId === categoryId) {
        setSelectedCategoryId(defaultCategory?.id ?? ALL_CATEGORY_ID);
      }
      if (effectiveDefaultSendCategoryId === categoryId) {
        setDefaultSendCategoryId(defaultCategory?.id ?? null);
      }
      await fetchData(false);
    } catch (error) {
      console.error(error);
    }
  };

  const completed = filteredMessages.filter((message) => message.isCleared);
  const pending = filteredMessages.filter((message) => !message.isCleared);

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
      <span className="admin-tag" style={{ background: color, marginLeft: '6px', fontSize: '10px', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
        {label}
        {isUnlimited && <span style={{ fontSize: '12px', lineHeight: 1 }}>∞</span>}
      </span>
    );
  };

  return (
    <div className={`app-container ${layoutMode === 'tiled' ? 'tiled-layout' : ''}`}>
      <div className="header">
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <img src="/logo.png" alt="Logo" style={{ width: '32px', height: '32px', borderRadius: '8px' }} />
          <h1 className="header-title">{t('app.name', 'Synca')}</h1>
        </div>
        <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
          {isAdmin && (
            <button className="header-btn" onClick={() => window.open('/admin', '_blank')} title="Admin Dashboard">
              <span style={{ fontSize: '12px', fontWeight: 500, color: 'var(--synca-purple)', padding: '0 4px' }}>Manage</span>
            </button>
          )}
          <button className="header-btn" onClick={() => setShowCategoryModal(true)} title="Manage categories">
            <Settings2 size={18} />
          </button>
          <button className="header-btn" onClick={() => setLayoutMode(layoutMode === 'single' ? 'tiled' : 'single')} title="Toggle layout">
            {layoutMode === 'single' ? <Grid2x2 size={18} /> : <Rows3 size={18} />}
          </button>
          <button className="header-btn" onClick={() => void handleRefresh()} title={t('message_list.sync_success', 'Sync')}>
            <RefreshCcw size={18} />
          </button>
          <button
            className="header-btn"
            onClick={() => setShowClearModal(true)}
            disabled={layoutMode === 'single' ? completed.length === 0 : messages.filter((message) => message.isCleared).length === 0}
            title={t('message_list.clear_all_confirm_title', 'Clear')}
            style={{ opacity: layoutMode === 'single' ? (completed.length === 0 ? 0.3 : 1) : (messages.filter((message) => message.isCleared).length === 0 ? 0.3 : 1) }}
          >
            <Trash2 size={18} />
          </button>

          <div style={{ width: '1px', height: '20px', background: 'var(--border-color)', margin: '0 8px', opacity: 0.8 }} />

          {email && (
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', padding: '4px 8px 4px 14px', borderRadius: '20px', background: 'rgba(0,0,0,0.03)', border: '1px solid var(--border-color)', whiteSpace: 'nowrap' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span style={{ fontSize: '12px', fontWeight: 500, opacity: 0.9 }}>{email}</span>
                {getPlanInfo()}
              </div>
              <button className="header-btn" onClick={() => setShowLogoutModal(true)} title={t('message_list.logout', 'Sign Out')} style={{ width: '28px', height: '28px', minWidth: '28px', background: 'transparent', margin: 0 }}>
                <LogOut size={14} />
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="category-toolbar">
        <div className="category-switcher">
          <button className={`category-chip ${selectedScopeIsAll ? 'active' : ''} color-slate`} onClick={() => setSelectedCategoryId(ALL_CATEGORY_ID)}>
            {t('common.all', 'All')}
          </button>
          {categories.map((category) => (
            <button
              key={category.id}
              className={`category-chip color-${category.color} ${selectedCategoryId === category.id ? 'active' : ''}`}
              onClick={() => setSelectedCategoryId(category.id)}
            >
              {category.name}
            </button>
          ))}
          <button className="category-add-btn" onClick={() => setShowCategoryModal(true)} title={t('message_list.manage_categories', 'Manage Categories')}>
            <Plus size={15} />
          </button>
        </div>

        {displayedSendCategoryId && (
          <label className={`default-send-picker ${selectedScopeIsAll ? '' : 'is-readonly'}`}>
            <span>{t('message_list.default_send_category', 'Send from All to')}</span>
            <select
              value={displayedSendCategoryId}
              onChange={(e) => setDefaultSendCategoryId(e.target.value)}
              disabled={!selectedScopeIsAll}
            >
              {categories.map((category) => (
                <option key={category.id} value={category.id}>
                  {category.name}
                </option>
              ))}
            </select>
          </label>
        )}
      </div>

      {layoutMode === 'tiled' ? (
        <div className="category-board" style={{ ['--category-column-width' as string]: tiledColumnWidth }}>
          {tiledCategories.map((category) => (
            <CategoryColumn
              key={category.id}
              category={category}
              messages={messages.filter((message) => message.categoryId === category.id)}
              categories={categories}
              isLoading={isLoading}
              onRefresh={handleRefresh}
              onClearCompleted={() => handleScopedClear(category.id)}
              onSent={() => fetchData(false)}
            />
          ))}
        </div>
      ) : (
        <>
          <div className="message-list" ref={listRef}>
            {isLoading && messages.length === 0 && <p style={{ textAlign: 'center', opacity: 0.5, marginTop: '20px' }}>{t('message_list.loading', 'Loading...')}</p>}

            {!isLoading && filteredMessages.length === 0 && (
              <div className="empty-state">
                <Lightbulb className="empty-state-icon" size={60} />
                <h2 className="empty-state-title">{t('app.name')}</h2>
                <p className="empty-state-slogan">{t('app.slogan')}</p>
              </div>
            )}

            {filteredMessages.length > 0 && (
              <>
                {completed.map((message) => (
                  <MessageBubble key={message.id} message={message} categories={categories} onUpdate={() => void fetchData(false)} />
                ))}

                {pending.length > 0 && (
                  <div style={{ marginTop: '8px', marginBottom: '4px' }}>
                    <span style={{ fontSize: '12px', fontWeight: 'bold', color: 'var(--text-secondary)', background: 'var(--border-color)', padding: '2px 8px', borderRadius: '4px' }}>
                      {t('message_list.todo_section', 'Inbox')}
                    </span>
                  </div>
                )}

                {pending.map((message) => (
                  <MessageBubble key={message.id} message={message} categories={categories} onUpdate={() => void fetchData(false)} />
                ))}
              </>
            )}
          </div>

          <InputBar categoryId={activeSendCategoryId} onSent={() => void fetchData(true)} />
        </>
      )}

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

      {showClearModal && (
        <Modal
          title={t('message_list.clear_all_confirm_title', 'Confirm Delete')}
          message={layoutMode === 'single'
            ? t('message_list.clear_current_category_confirm', 'This will delete completed items in the current category')
            : t('message_list.clear_all_categories_confirm', 'This will delete completed items in all categories')}
          confirmText={t('common.delete', 'Delete')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={async () => {
            setShowClearModal(false);
            await handleScopedClear(layoutMode === 'single' && !selectedScopeIsAll ? selectedCategoryId : null);
          }}
          onCancel={() => setShowClearModal(false)}
          destructive
        />
      )}

      {showCategoryModal && (
        <Modal
          title={t('message_list.manage_categories', 'Manage Categories')}
          message=""
          confirmText={t('common.ok', 'OK')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={() => setShowCategoryModal(false)}
          onCancel={() => setShowCategoryModal(false)}
        >
          <div className="category-manager">
            <div className="category-create-row">
              <input
                className="category-name-input"
                value={newCategoryName}
                onChange={(e) => setNewCategoryName(e.target.value)}
                placeholder={t('message_list.new_category_placeholder', 'New category')}
              />
              <div className="category-color-select-wrap">
                <span className={`category-color-dot color-${newCategoryColor}`} />
                <select value={newCategoryColor} onChange={(e) => setNewCategoryColor(e.target.value as MessageCategoryColor)}>
                  {CATEGORY_COLORS.map((color) => (
                    <option key={color} value={color}>{COLOR_LABELS[color]}</option>
                  ))}
                </select>
              </div>
              <button className="category-add-action" onClick={() => void handleCreateCategory()}>
                <Plus size={14} />
                <span>{t('common.add', 'Add')}</span>
              </button>
            </div>

            <div className="category-manager-list">
              {categories.map((category) => (
                <div key={category.id} className="category-manager-row">
                  <span className={`category-chip color-${category.color}`}>{category.name}</span>
                  {selectedScopeIsAll && (
                    <label className="category-default-radio">
                      <input
                        type="radio"
                        checked={effectiveDefaultSendCategoryId === category.id}
                        onChange={() => setDefaultSendCategoryId(category.id)}
                      />
                      <span>{t('message_list.default_send_target', 'Default send')}</span>
                    </label>
                  )}
                  {!category.isDefault && (
                    <>
                      <input
                        className="category-inline-input"
                        defaultValue={category.name}
                        onBlur={(e) => {
                          const value = e.target.value.trim();
                          if (value && value !== category.name) {
                            void handleCategoryUpdate(category, { name: value });
                          }
                        }}
                      />
                      <div className="category-color-select-wrap">
                        <span className={`category-color-dot color-${category.color}`} />
                        <select
                          value={category.color}
                          onChange={(e) => void handleCategoryUpdate(category, { color: e.target.value as MessageCategoryColor })}
                        >
                          {CATEGORY_COLORS.map((color) => (
                            <option key={color} value={color}>{COLOR_LABELS[color]}</option>
                          ))}
                        </select>
                      </div>
                      <button className="header-btn" onClick={() => void handleCategoryDelete(category.id)} title={t('common.delete', 'Delete')}>
                        <Trash2 size={16} />
                      </button>
                    </>
                  )}
                </div>
              ))}
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};
