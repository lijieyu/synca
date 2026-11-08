import { SettingsPanel } from './SettingsPanel';
import { FunctionMenu } from './FunctionMenu';
import { ShellPanel } from './ShellPanel';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { api, type MessageCategory, type MessageCategoryColor, type SyncaMessage } from '../api/client';
import { MessageBubble } from './MessageBubble';
import { MessageTextEditor } from './MessageTextEditor';
import { InputBar } from './InputBar';
import { useAuth } from '../contexts/AuthContext';
import { ChevronDown, ChevronUp, Lightbulb, Plus, RefreshCcw, Trash2 } from 'lucide-react';
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
const formatTodoBadgeCount = (count: number) => (count > 99 ? '99+' : String(count));

const CategoryTodoBadge: React.FC<{ count: number }> = ({ count }) => {
  const { t } = useTranslation();
  if (count <= 0) return null;
  return <span className="category-todo-badge" aria-label={t('preferences.pending_count', { count })}>{formatTodoBadgeCount(count)}</span>;
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

export const MessageListView: React.FC = () => {
  const [editingMessage, setEditingMessage] = useState<SyncaMessage | null>(null);
  const [panel, setPanel] = useState<'account' | 'feedback' | 'about' | null>(null);
  const [messages, setMessages] = useState<SyncaMessage[]>([]);
  const [categories, setCategories] = useState<MessageCategory[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [composerFocusRequest, requestComposerFocus] = useState(0);
  const [selectedCategoryId, setSelectedCategoryId] = useState<string>(ALL_CATEGORY_ID);
  const [showSettings, setShowSettings] = useState(false);
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
  const [editingCategory, setEditingCategory] = useState<MessageCategory | null>(null);
  const [discardCategoryAction, setDiscardCategoryAction] = useState<(() => void) | null>(null);
  const [categorySaving, setCategorySaving] = useState(false);
  const [newCategoryName, setNewCategoryName] = useState('');
  const [newCategoryColor, setNewCategoryColor] = useState<MessageCategoryColor>('sky');
  const listRef = useRef<HTMLDivElement>(null);
  const didRestorePreferencesRef = useRef(false);
  const fetchRevision = useRef(0);
  const pendingFetches = useRef(0);

  const { logout, email, plan, accessStatus, refreshAccessStatus } = useAuth();
  const { t } = useTranslation();

  const fetchData = async (scrollToBottom = false) => {
    const revision = ++fetchRevision.current;
    const token = localStorage.getItem('authToken');
    pendingFetches.current += 1;
    try {
      const [messagesRes, categoriesRes] = await Promise.all([
        api.listMessages(),
        api.listMessageCategories(),
      ]);

      if (revision !== fetchRevision.current || token !== localStorage.getItem('authToken')) return false;
      const sortedMessages = sortMessages(messagesRes.messages);
      setMessages(sortedMessages);
      setCategories(categoriesRes.categories);
      refreshAccessStatus();

      const defaultCategory = categoriesRes.categories.find((category) => category.isDefault) ?? categoriesRes.categories[0];
      const storedSelected = localStorage.getItem(categoryScopeStorageKey(email)) ?? ALL_CATEGORY_ID;
      const storedDefaultSend = localStorage.getItem(defaultSendCategoryStorageKey(email));

      if (!didRestorePreferencesRef.current) {
        setSelectedCategoryId(
          storedSelected === ALL_CATEGORY_ID || categoriesRes.categories.some((category) => category.id === storedSelected)
            ? storedSelected
            : ALL_CATEGORY_ID
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
      return true;
    } catch (error) {
      console.error(error);
      return false;
    } finally {
      pendingFetches.current -= 1;
      if (revision === fetchRevision.current) setIsLoading(false);
    }
  };

  useEffect(() => {
    didRestorePreferencesRef.current = false;
    void fetchData(true);
    const poll = () => {
      if (!document.hidden && pendingFetches.current === 0) void fetchData(false);
    };
    const timer = setInterval(poll, 10000);
    document.addEventListener('visibilitychange', poll);
    return () => {
      ++fetchRevision.current;
      clearInterval(timer);
      document.removeEventListener('visibilitychange', poll);
    };
  }, [email]);

  useEffect(() => {
    // Do not overwrite the saved selection before this account's categories load.
    if (!didRestorePreferencesRef.current) return;
    localStorage.setItem(categoryScopeStorageKey(email), selectedCategoryId);
  }, [email, selectedCategoryId]);

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
  const handleRefresh = async () => {
    if (!await fetchData(false)) return;
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
    if (!trimmedName || categorySaving) return;
    const duplicated = categories.some((category) => category.id !== editingCategory?.id && category.name.trim().toLocaleLowerCase() === trimmedName.toLocaleLowerCase());
    if (duplicated) {
      setShowDuplicateCategoryModal(true);
      return;
    }
    setCategorySaving(true);
    try {
      if (editingCategory) await api.updateMessageCategory(editingCategory.id, { name: trimmedName, color: newCategoryColor });
      else await api.createMessageCategory(trimmedName, newCategoryColor);
      setEditingCategory(null);
      setNewCategoryName('');
      setNewCategoryColor('sky');
      setShowCreateCategoryModal(false);
      await fetchData(false);
    } catch (error) {
      console.error(error);
      setCategoryManagerError({ title: t('common.error'), message: t('navigation.save_failed') });
    } finally { setCategorySaving(false); }
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

  const activateCategory = (id: string) => {
    setSelectedCategoryId(id);
    requestComposerFocus(value => value + 1);
  };

  const navigateCategories = (event: React.KeyboardEvent<HTMLButtonElement>) => {
    if (!['ArrowDown', 'ArrowUp', 'ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const buttons = Array.from(event.currentTarget.parentElement!.querySelectorAll<HTMLButtonElement>('[data-category-id]'));
    const index = buttons.indexOf(event.currentTarget);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1
      : Math.max(0, Math.min(buttons.length - 1, index + (['ArrowDown', 'ArrowRight'].includes(event.key) ? 1 : -1)));
    buttons[next].focus();
    setSelectedCategoryId(buttons[next].dataset.categoryId!);
  };

  const completed = filteredMessages.filter((message) => message.isCleared);
  const pending = filteredMessages.filter((message) => !message.isCleared);

  return (
    <div className="app-container calm-shell">
      {panel && <ShellPanel kind={panel} email={email} onClose={() => setPanel(null)} onLogout={() => { setPanel(null); setShowLogoutModal(true); }} />}
      {showSettings && <SettingsPanel onClose={() => setShowSettings(false)} />}
      <aside className="calm-sidebar">
        <div className="sidebar-brand"><img src="/logo.png?v=a2" alt="" /><span>Synca</span></div>

        <div className="category-toolbar">
          <div className="category-switcher">
            <button className={`category-chip has-badge ${selectedScopeIsAll ? 'active' : ''} color-slate`} data-category-id={ALL_CATEGORY_ID} onKeyDown={navigateCategories} onClick={() => activateCategory(ALL_CATEGORY_ID)}>
              {t('common.all', 'All')}
              <CategoryTodoBadge count={allTodoCount} />
            </button>
            {visibleSingleModeCategories.map((category) => (
              <button
                key={category.id}
                className={`category-chip has-badge color-${category.color} ${selectedCategoryId === category.id ? 'active' : ''}`}
                data-category-id={category.id}
                onClick={() => activateCategory(category.id)}
                onDoubleClick={() => { if (category.isDefault) return; setEditingCategory(category); setNewCategoryName(category.name); setNewCategoryColor(category.color); setShowCreateCategoryModal(true); }}
                onKeyDown={e => { navigateCategories(e); if (e.key === 'F2' && !category.isDefault) { e.preventDefault(); setEditingCategory(category); setNewCategoryName(category.name); setNewCategoryColor(category.color); setShowCreateCategoryModal(true); } }}
              >
                {category.isDefault ? t('message_category.default_badge', 'Default') : category.name}
                <CategoryTodoBadge count={todoCountByCategoryId[category.id] ?? 0} />
              </button>
            ))}
            <button className="category-add-btn" onClick={() => { setEditingCategory(null); setNewCategoryName(''); setNewCategoryColor('sky'); setShowCreateCategoryModal(true); }} title={t('message_category.new_section')}>
              <Plus size={15} /><span>{t('message_category.add_action')}</span>
            </button>
          </div>

        </div>
      <FunctionMenu email={email} planLabel={t(!accessStatus ? 'message_list.loading' : accessStatus.isUnlimited ? 'access.status_unlimited' : 'access.free_title')}
        usage={plan === 'free' && accessStatus ? { used: accessStatus.todayUsed, limit: accessStatus.todayLimit ?? 20 } : null}
        onAccount={() => setPanel('account')} onSettings={() => setShowSettings(true)} onCategories={openCategoryManager}
        onFeedback={() => setPanel('feedback')} onAbout={() => setPanel('about')} onLogout={() => setShowLogoutModal(true)} />
      </aside>
      <main className="calm-main">
        <header className="header">
          <div className="stream-heading"><h1>{selectedScopeIsAll ? t('common.all') : categories.find(c => c.id === selectedCategoryId)?.isDefault ? t('message_category.default_badge') : categories.find(c => c.id === selectedCategoryId)?.name}</h1>
          <p>{t('preferences.pending_count', { count: pending.length })}</p></div>
          <div className="header-actions">
            <button className="header-btn" onClick={() => void handleRefresh()} aria-label={t('navigation.sync')} title={t('navigation.sync')}><RefreshCcw size={18} /></button>
            <button className="header-btn" disabled={!completed.length} onClick={() => setShowClearModal(true)} aria-label={t('message_list.clear_all_confirm_title')} title={t('message_list.clear_all_confirm_title')}><Trash2 size={18} /></button>
          </div>
        </header>
          <div className="message-list" ref={listRef}>
            {isLoading && messages.length === 0 && <p style={{ textAlign: 'center', opacity: 0.5, marginTop: '20px' }}>{t('message_list.loading', 'Loading...')}</p>}

            {!isLoading && filteredMessages.length === 0 && (
              <EmptyMessageState />
            )}

            {filteredMessages.length > 0 && (
              <>
                {completed.map((message) => (
                  <MessageBubble key={message.id} message={message} categories={categories} onEdit={message => setEditingMessage({ ...message })} onUpdate={() => void fetchData(false)} />
                ))}

                {pending.length > 0 && (
                  <div style={{ marginTop: '8px', marginBottom: '4px' }}>
                    <span style={{ fontSize: '12px', fontWeight: 'bold', color: 'var(--text-secondary)', background: 'var(--border-color)', padding: '2px 8px', borderRadius: '4px' }}>
                      {t('message_list.todo_section', 'Inbox')}
                    </span>
                  </div>
                )}

                {pending.map((message) => (
                  <MessageBubble key={message.id} message={message} categories={categories} onEdit={message => setEditingMessage({ ...message })} onUpdate={() => void fetchData(false)} />
                ))}
              </>
            )}
          </div>

          <InputBar focusRequest={composerFocusRequest} categoryId={activeSendCategoryId} onSent={() => void fetchData(true)} />
      </main>

      {editingMessage && <MessageTextEditor key={editingMessage.id} message={editingMessage}
        onCancel={() => setEditingMessage(null)} onSaved={updated => {
          setEditingMessage(null);
          ++fetchRevision.current;
          setMessages(current => sortMessages(current.map(item => item.id === updated.id && Date.parse(updated.updatedAt) >= Date.parse(item.updatedAt) ? updated : item)));
          setToastMsg(t('message_edit.saved')); setShowToast(true);
          void fetchData(false);
        }} />}

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
          message={!selectedScopeIsAll
            ? t('message_list.clear_current_category_confirm', 'This will delete completed items in the current category')
            : t('message_list.clear_all_categories_confirm', 'This will delete completed items in all categories')}
          confirmText={t('common.delete', 'Delete')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={async () => {
            setShowClearModal(false);
            await handleScopedClear(!selectedScopeIsAll ? selectedCategoryId : null);
          }}
          onCancel={() => setShowClearModal(false)}
          destructive
        />
      )}

      {showCreateCategoryModal && (
        <Modal
          className="category-editor-modal"
          title={t(editingCategory ? 'message_category.edit_title' : 'message_category.new_section')}
          message=""
          confirmText={t(editingCategory ? 'common.save' : 'message_category.add_action')}
          confirmDisabled={categorySaving || !newCategoryName.trim()} closeDisabled={categorySaving} cancelDisabled={categorySaving}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={() => void handleCreateCategory()}
          onCancel={() => { if (categorySaving) return; const changed = editingCategory ? newCategoryName !== editingCategory.name || newCategoryColor !== editingCategory.color : !!newCategoryName.trim() || newCategoryColor !== 'sky'; if (changed) setDiscardCategoryAction(() => () => setShowCreateCategoryModal(false)); else setShowCreateCategoryModal(false); }}
          leadingActionText={editingCategory ? undefined : t('message_list.manage_categories', 'Categories')}
          onLeadingAction={() => {
            const open = () => { setShowCreateCategoryModal(false); openCategoryManager(); };
            if (newCategoryName.trim() || newCategoryColor !== 'sky') setDiscardCategoryAction(() => open); else open();
          }}
          size="compact"
        >
          <div className="category-create-stack">
            <input
              className="category-name-input"
              data-initial-focus
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
                  role="radio" aria-checked={newCategoryColor === color}
                  title={t(`preferences.colors.${color}`, COLOR_LABELS[color])}
                />
              ))}
            </div>
          </div>
        </Modal>
      )}

      {discardCategoryAction && <Modal title={t('message_edit.discard_title')} message="" confirmText={t('message_edit.discard')} cancelText={t('common.cancel')} destructive onCancel={() => setDiscardCategoryAction(null)} onConfirm={() => { discardCategoryAction(); setDiscardCategoryAction(null); }} />}

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
        <Modal size="large"
          title={t('message_list.manage_categories', 'Manage Categories')}
          closeLabel={t('navigation.close')}
          message=""
          confirmText={t('common.save', 'Save')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={() => void handleCategoryManagerSave()}
          onCancel={() => { if (JSON.stringify(categoryManagerRows) !== JSON.stringify(buildCategoryManagerRows())) setDiscardCategoryAction(() => () => setShowCategoryModal(false)); else setShowCategoryModal(false); }}
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
                        <option key={color} value={color}>{t(`preferences.colors.${color}`, COLOR_LABELS[color])}</option>
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
