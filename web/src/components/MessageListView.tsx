import React, { useEffect, useMemo, useRef, useState } from 'react';
import { api, type MessageCategory, type MessageCategoryColor, type SyncaMessage } from '../api/client';
import { MessageBubble } from './MessageBubble';
import { InputBar } from './InputBar';
import { useAuth } from '../contexts/AuthContext';
import { ChevronDown, ChevronUp, Grid2x2, Lightbulb, LogOut, Plus, RefreshCcw, Rows3, Settings2, Trash2 } from 'lucide-react';
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

interface CategoryManagerDraftRow {
  clientId: string;
  id?: string;
  name: string;
  color: MessageCategoryColor;
}

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
const layoutGlobalStorageKey = 'synca.messageLayout';
const layoutStorageKey = (email: string | null) => `synca.messageLayout.${email ?? 'guest'}`;
const readStoredLayoutMode = (email: string | null): 'single' | 'tiled' => {
  const storedLayout = localStorage.getItem(layoutStorageKey(email)) ?? localStorage.getItem(layoutGlobalStorageKey);
  return storedLayout === 'tiled' ? 'tiled' : 'single';
};

const formatTodoBadgeCount = (count: number) => (count > 99 ? '99+' : String(count));

const CategoryTodoBadge: React.FC<{ count: number }> = ({ count }) => {
  if (count <= 0) return null;
  return <span className="category-todo-badge" aria-label={`${count} todos`}>{formatTodoBadgeCount(count)}</span>;
};

const EmptyMessageState: React.FC = () => {
  const { t } = useTranslation();

  return (
    <div className="empty-state">
      <Lightbulb className="empty-state-icon" size={60} />
      <h2 className="empty-state-title">{t('app.name')}</h2>
      <p className="empty-state-slogan">{t('app.slogan')}</p>
    </div>
  );
};

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
          <span className={`category-chip has-badge color-${category.color}`}>
            {category.name}
            <CategoryTodoBadge count={pending.length} />
          </span>
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
        {!isLoading && messages.length === 0 && <EmptyMessageState />}

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
  const [layoutMode, setLayoutMode] = useState<'single' | 'tiled'>(() => readStoredLayoutMode(null));
  const [defaultSendCategoryId, setDefaultSendCategoryId] = useState<string | null>(null);
  const [showToast, setShowToast] = useState(false);
  const [toastMsg, setToastMsg] = useState('');
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showClearModal, setShowClearModal] = useState(false);
  const [showCreateCategoryModal, setShowCreateCategoryModal] = useState(false);
  const [showDuplicateCategoryModal, setShowDuplicateCategoryModal] = useState(false);
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [categoryManagerRows, setCategoryManagerRows] = useState<CategoryManagerDraftRow[]>([]);
  const [categoryManagerDeleteTarget, setCategoryManagerDeleteTarget] = useState<CategoryManagerDraftRow | null>(null);
  const [categoryManagerError, setCategoryManagerError] = useState<{ title: string; message: string } | null>(null);
  const [newCategoryName, setNewCategoryName] = useState('');
  const [newCategoryColor, setNewCategoryColor] = useState<MessageCategoryColor>('sky');
  const listRef = useRef<HTMLDivElement>(null);
  const didRestorePreferencesRef = useRef(false);

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

      if (!didRestorePreferencesRef.current) {
        setLayoutMode(readStoredLayoutMode(email));
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
        didRestorePreferencesRef.current = true;
      }

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
    didRestorePreferencesRef.current = false;
    void fetchData(true);
    const timer = setInterval(() => void fetchData(false), 10000);
    return () => clearInterval(timer);
  }, [email]);

  useEffect(() => {
    localStorage.setItem(categoryScopeStorageKey(email), selectedCategoryId);
  }, [email, selectedCategoryId]);

  useEffect(() => {
    localStorage.setItem(layoutStorageKey(email), layoutMode);
    localStorage.setItem(layoutGlobalStorageKey, layoutMode);
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

  const filteredMessages = useMemo(() => {
    if (selectedCategoryId === ALL_CATEGORY_ID) return messages;
    return messages.filter((message) => message.categoryId === selectedCategoryId);
  }, [messages, selectedCategoryId]);

  const todoCountByCategoryId = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const message of messages) {
      if (message.isCleared || !message.categoryId) continue;
      counts[message.categoryId] = (counts[message.categoryId] ?? 0) + 1;
    }
    return counts;
  }, [messages]);
  const allTodoCount = useMemo(() => messages.filter((message) => !message.isCleared).length, [messages]);
  const visibleSingleModeCategories = useMemo(() => categories, [categories]);
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

  const buildCategoryManagerRows = () =>
    categories
      .filter((category) => !category.isDefault)
      .map((category) => ({
        clientId: category.id,
        id: category.id,
        name: category.name,
        color: category.color,
      }));

  const openCategoryManager = () => {
    setCategoryManagerRows(buildCategoryManagerRows());
    setCategoryManagerDeleteTarget(null);
    setCategoryManagerError(null);
    setShowCategoryModal(true);
  };

  const updateCategoryManagerRow = (clientId: string, patch: Partial<Pick<CategoryManagerDraftRow, 'name' | 'color'>>) => {
    setCategoryManagerRows((rows) => rows.map((row) => (row.clientId === clientId ? { ...row, ...patch } : row)));
  };

  const moveCategoryManagerRow = (index: number, direction: -1 | 1) => {
    setCategoryManagerRows((rows) => {
      const targetIndex = index + direction;
      if (index < 0 || targetIndex < 0 || index >= rows.length || targetIndex >= rows.length) return rows;
      const next = [...rows];
      const [row] = next.splice(index, 1);
      next.splice(targetIndex, 0, row);
      return next;
    });
  };

  const addCategoryManagerRow = () => {
    setCategoryManagerRows((rows) => [
      ...rows,
      {
        clientId: `new-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        name: '',
        color: 'sky',
      },
    ]);
  };

  const handleScopedClear = async (categoryId?: string | null) => {
    await api.deleteCompletedMessages(categoryId ?? null);
    await fetchData(false);
  };

  const handleCreateCategory = async () => {
    const trimmedName = newCategoryName.trim();
    if (!trimmedName) return;
    const duplicated = categories.some((category) => category.name.trim().toLocaleLowerCase() === trimmedName.toLocaleLowerCase());
    if (duplicated) {
      setShowDuplicateCategoryModal(true);
      return;
    }
    try {
      await api.createMessageCategory(trimmedName, newCategoryColor);
      setNewCategoryName('');
      setNewCategoryColor('sky');
      setShowCreateCategoryModal(false);
      await fetchData(false);
    } catch (error) {
      console.error(error);
    }
  };

  const handleCategoryManagerSave = async () => {
    const normalizedNames = categoryManagerRows.map((row) => row.name.trim());
    if (normalizedNames.some((name) => !name)) {
      setCategoryManagerError({
        title: t('message_category.invalid_title', 'Category Name Required'),
        message: t('message_category.invalid_message', 'Each category needs a name before saving.'),
      });
      return;
    }

    const seenNames = new Set<string>();
    for (const name of normalizedNames) {
      const key = name.toLocaleLowerCase();
      if (seenNames.has(key)) {
        setCategoryManagerError({
          title: t('message_category.duplicate_title', 'Category Already Exists'),
          message: t('message_category.duplicate_message', 'Use a different category name.'),
        });
        return;
      }
      seenNames.add(key);
    }

    const originalCategories = categories.filter((category) => !category.isDefault);
    const originalById = new Map(originalCategories.map((category) => [category.id, category]));
    const keptIds = new Set(categoryManagerRows.flatMap((row) => (row.id ? [row.id] : [])));

    try {
      for (const category of originalCategories) {
        if (!keptIds.has(category.id)) {
          await api.deleteMessageCategory(category.id);
        }
      }

      const orderedCategoryIds: string[] = [];

      for (const row of categoryManagerRows) {
        const name = row.name.trim();
        if (!row.id) {
          const created = await api.createMessageCategory(name, row.color);
          orderedCategoryIds.push(created.id);
          continue;
        }

        const original = originalById.get(row.id);
        if (!original) continue;
        const patch: Partial<Pick<MessageCategory, 'name' | 'color'>> = {};
        if (name !== original.name) patch.name = name;
        if (row.color !== original.color) patch.color = row.color;
        if (Object.keys(patch).length > 0) {
          await api.updateMessageCategory(row.id, patch);
        }
        orderedCategoryIds.push(row.id);
      }

      await api.reorderMessageCategories(orderedCategoryIds);
      setShowCategoryModal(false);
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
          <button className="header-btn" onClick={openCategoryManager} title="Manage categories">
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

      {layoutMode === 'single' && (
        <div className="category-toolbar">
          <div className="category-switcher">
            <button className={`category-chip has-badge ${selectedScopeIsAll ? 'active' : ''} color-slate`} onClick={() => setSelectedCategoryId(ALL_CATEGORY_ID)}>
              {t('common.all', 'All')}
              <CategoryTodoBadge count={allTodoCount} />
            </button>
            {visibleSingleModeCategories.map((category) => (
              <button
                key={category.id}
                className={`category-chip has-badge color-${category.color} ${selectedCategoryId === category.id ? 'active' : ''}`}
                onClick={() => setSelectedCategoryId(category.id)}
              >
                {category.name}
                <CategoryTodoBadge count={todoCountByCategoryId[category.id] ?? 0} />
              </button>
            ))}
            <button className="category-add-btn" onClick={() => setShowCreateCategoryModal(true)} title={t('message_category.new_section', 'New Category')}>
              <Plus size={15} />
            </button>
          </div>

        </div>
      )}

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
              <EmptyMessageState />
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

      {showCreateCategoryModal && (
        <Modal
          title={t('message_category.new_section', 'New Category')}
          message=""
          confirmText={t('message_category.add_action', 'Add Category')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={() => void handleCreateCategory()}
          onCancel={() => setShowCreateCategoryModal(false)}
          leadingActionText={t('message_list.manage_categories', 'Categories')}
          onLeadingAction={() => {
            setShowCreateCategoryModal(false);
            openCategoryManager();
          }}
          size="compact"
        >
          <div className="category-create-stack">
            <input
              className="category-name-input"
              value={newCategoryName}
              onChange={(e) => setNewCategoryName(e.target.value)}
              placeholder={t('message_category.name_placeholder', 'Category name')}
              autoFocus
            />

            <div className="category-swatch-grid" role="radiogroup" aria-label={t('message_category.color_label', 'Color')}>
              {CATEGORY_COLORS.map((color) => (
                <button
                  key={color}
                  type="button"
                  className={`category-swatch color-${color} ${newCategoryColor === color ? 'active' : ''}`}
                  onClick={() => setNewCategoryColor(color)}
                  aria-checked={newCategoryColor === color}
                  title={COLOR_LABELS[color]}
                />
              ))}
            </div>
          </div>
        </Modal>
      )}

      {showDuplicateCategoryModal && (
        <Modal
          title={t('message_category.duplicate_title', 'Category Already Exists')}
          message={t('message_category.duplicate_message', 'Use a different category name.')}
          confirmText={t('common.ok', 'OK')}
          onConfirm={() => setShowDuplicateCategoryModal(false)}
          onCancel={() => setShowDuplicateCategoryModal(false)}
          size="compact"
        />
      )}

      {showCategoryModal && (
        <Modal
          title={t('message_list.manage_categories', 'Manage Categories')}
          message=""
          confirmText={t('common.save', 'Save')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={() => void handleCategoryManagerSave()}
          onCancel={() => setShowCategoryModal(false)}
        >
          <div className="category-manager">
            <div className="category-manager-list">
              <div className="category-manager-heading" role="row">
                <span>{t('message_category.name_column', 'Name')}</span>
                <span>{t('message_category.color_label', 'Color')}</span>
                <span aria-hidden="true" />
                <span aria-hidden="true" />
              </div>

              {categoryManagerRows.map((row, index) => (
                <section key={row.clientId} className="category-list-row">
                  <span className={`category-row-accent color-${row.color}`} aria-hidden="true" />
                  <input
                    className="category-inline-input"
                    value={row.name}
                    onChange={(e) => updateCategoryManagerRow(row.clientId, { name: e.target.value })}
                    placeholder={t('message_category.name_placeholder', 'Category name')}
                  />

                  <label className="category-color-field">
                    <span className={`category-color-dot color-${row.color}`} aria-hidden="true" />
                    <select
                      className="category-color-select"
                      value={row.color}
                      onChange={(e) => updateCategoryManagerRow(row.clientId, { color: e.target.value as MessageCategoryColor })}
                      aria-label={t('message_category.color_label', 'Color')}
                    >
                      {CATEGORY_COLORS.map((color) => (
                        <option key={color} value={color}>{COLOR_LABELS[color]}</option>
                      ))}
                    </select>
                  </label>

                  <button
                    className="category-row-delete"
                    onClick={() => setCategoryManagerDeleteTarget(row)}
                    title={t('message_category.delete_action', 'Delete Category')}
                  >
                    <Trash2 size={16} />
                  </button>

                  <div className="category-row-move" aria-label={t('message_category.reorder_label', 'Reorder category')}>
                    <button
                      onClick={() => moveCategoryManagerRow(index, -1)}
                      disabled={index === 0}
                      title={t('message_category.move_up', 'Move Up')}
                    >
                      <ChevronUp size={15} />
                    </button>
                    <button
                      onClick={() => moveCategoryManagerRow(index, 1)}
                      disabled={index === categoryManagerRows.length - 1}
                      title={t('message_category.move_down', 'Move Down')}
                    >
                      <ChevronDown size={15} />
                    </button>
                  </div>
                </section>
              ))}

              <button className="category-add-row-btn" onClick={addCategoryManagerRow}>
                <Plus size={15} />
                <span>{t('message_category.add_action', 'Add Category')}</span>
              </button>
            </div>
          </div>
        </Modal>
      )}

      {categoryManagerDeleteTarget && (
        <Modal
          title={t('message_category.delete_confirm_title', 'Delete Category?')}
          message={t('message_category.delete_confirm_message', 'This category will be removed after you save.')}
          confirmText={t('common.delete', 'Delete')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={() => {
            setCategoryManagerRows((rows) => rows.filter((row) => row.clientId !== categoryManagerDeleteTarget.clientId));
            setCategoryManagerDeleteTarget(null);
          }}
          onCancel={() => setCategoryManagerDeleteTarget(null)}
          destructive
          size="compact"
        />
      )}

      {categoryManagerError && (
        <Modal
          title={categoryManagerError.title}
          message={categoryManagerError.message}
          confirmText={t('common.ok', 'OK')}
          onConfirm={() => setCategoryManagerError(null)}
          onCancel={() => setCategoryManagerError(null)}
          size="compact"
        />
      )}
    </div>
  );
};
