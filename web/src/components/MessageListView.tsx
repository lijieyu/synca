import { UpdateNotice } from './UpdateNotice';
import { FileText } from 'lucide-react';
import { Scratchpad } from './Scratchpad';
import { createChangeNotifications } from '../utils/changeNotifications';
import type { SyncState } from '../api/client';
import { mergeMessageChanges, messageChangesSince, nextMessageCheckpoint } from '../utils/messageSync';
import { SyncFeedback } from './SyncFeedback';
import { desktopClearShortcut } from '../utils/desktopShortcuts';
import { MobileCategoryDrawer } from './MobileCategoryDrawer';
import { SettingsSurface } from './SettingsSurface';
import { recordsInArea, taskCounts } from '../utils/collections';
import { PanelLeft, X, Tags, Bookmark } from 'lucide-react';
import { categoryEditPatch } from '../utils/categoryEdit';
import { AppLoading } from './AppLoading';
import { CategoryContextMenu, type CategoryMenuAnchor } from './CategoryContextMenu';
import { SidebarFrame } from './SidebarFrame';
import { AIPage } from './AIPage';
import { moveItem, usePointerSort } from '../hooks/usePointerSort';
import { CategoryPalette, categoryStyle } from './CategoryPalette';
import { BroomIcon } from './BroomIcon';
import { openSettings } from './SettingsPanel';
import { FunctionMenu } from './FunctionMenu';
import { ShellPanel } from './ShellPanel';
import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { api, type MessageCategory, type MessageCategoryColor, type SyncaMessage } from '../api/client';
import { MessageBubble } from './MessageBubble';
import { MessageTextEditor } from './MessageTextEditor';
import { InputBar } from './InputBar';
import { useAuth } from '../contexts/AuthContext';
import { Lightbulb, GripVertical, Trash2, Plus, RotateCw, Search, LayoutGrid } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Toast } from './Toast';
import { Modal } from './Modal';
import './CategoryManager.css';
import { MessageSearch } from './MessageSearch';
import { revealSearchTarget } from '../utils/revealSearchTarget';

const ALL_CATEGORY_ID = '__all__';

interface CategoryManagerDraftRow {
  clientId: string;
  id?: string;
  name: string;
  color: MessageCategoryColor;
  colorHex?: string | null;
  isDefault?: boolean;
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
  const [compact, setCompact] = useState(() => matchMedia('(width < 640px)').matches);
  const [drawerOpen, setDrawerOpen] = useState(false);
  useEffect(() => {
    const media=matchMedia('(width < 640px)');
    const resize=()=>{setCompact(media.matches);setDrawerOpen(false)};
    media.addEventListener('change',resize);
    return ()=>media.removeEventListener('change',resize);
  }, []);
  useEffect(() => {
    if (!compact || drawerOpen) return;
    let origin: Touch | undefined;
    const begin=(e:TouchEvent)=>{
      const t=e.touches[0];
      origin=e.touches.length===1 && t.clientX<=36 && e.target instanceof Element &&
        e.target.closest('.calm-main') && !e.target.closest('input,textarea,button,a') &&
        !document.querySelector('[aria-modal=true],dialog[open]') ? t : undefined;
    };
    const end=(e:TouchEvent)=>{
      const t=e.changedTouches[0];
      if(origin && t.clientX-origin.clientX>60 && t.clientX-origin.clientX>2*Math.abs(t.clientY-origin.clientY))setDrawerOpen(true);
      origin=undefined;
    };
    const cancel=()=>{origin=undefined};
    document.addEventListener('touchstart',begin,{passive:true});document.addEventListener('touchend',end,{passive:true});document.addEventListener('touchcancel',cancel);
    return ()=>{document.removeEventListener('touchstart',begin);document.removeEventListener('touchend',end);document.removeEventListener('touchcancel',cancel)};
  }, [compact,drawerOpen]);
  const [showSearch, setShowSearch] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  useEffect(() => {
    const keyboardNavigation = (event: KeyboardEvent) => { if (event.key === 'Tab') setSearchPointerOpened(false); };
    window.addEventListener('keydown', keyboardNavigation, true);
    return () => window.removeEventListener('keydown', keyboardNavigation, true);
  }, []);
  const [searchPointerOpened, setSearchPointerOpened] = useState(false);
  const [searchTarget, setSearchTarget] = useState<{id: string; nonce: number; matchedText?: string} | null>(null);
  const scrollRevision = useRef(0);
  const searchNavigation = useRef(false);
  const [categoryMenu, setCategoryMenu] = useState<CategoryMenuAnchor | null>(null);
  const [editingMessage, setEditingMessage] = useState<SyncaMessage | null>(null);
  const [panel, setPanel] = useState<'account' | 'feedback' | 'about' | null>(null);
  const [messages, setMessages] = useState<SyncaMessage[]>([]);
  const [categories, setCategories] = useState<MessageCategory[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [composerFocusRequest, requestComposerFocus] = useState(0);
  const [showScratchpad, setShowScratchpad] = useState(false);
  const [showCollections, setShowCollections] = useState(false);
  const collectionsViewRef = useRef(false);
  collectionsViewRef.current = showCollections;
  const [collectionCategory, setCollectionCategory] = useState(ALL_CATEGORY_ID);
  const [selectedCategoryId, setSelectedCategoryId] = useState<string>(ALL_CATEGORY_ID);
  const [defaultSendCategoryId, setDefaultSendCategoryId] = useState<string | null>(null);
  const [showToast, setShowToast] = useState(false);
  const [toastMsg, setToastMsg] = useState('');
  const [showAI, setShowAI] = useState(false);
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showClearModal, setShowClearModal] = useState(false);
  const [showCreateCategoryModal, setShowCreateCategoryModal] = useState(false);
  const [duplicateName, setDuplicateName] = useState(false);
  const categoryNameInput = useRef<HTMLInputElement>(null);
  const managerNames = useRef(new Map<string, HTMLInputElement>());
  const [managerInvalid, setManagerInvalid] = useState<{id: string; message: string} | null>(null);
  const [managerEditing, setManagerEditing] = useState(false);
  const [clearing, setClearing] = useState(false);
  const [clearError, setClearError] = useState(false);
  useEffect(() => { if (!showCreateCategoryModal) setDuplicateName(false); }, [showCreateCategoryModal]);
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [categoryManagerEditor, setCategoryManagerEditor] = useState<CategoryManagerDraftRow | null>(null);
  const [categoryManagerRows, setCategoryManagerRows] = useState<CategoryManagerDraftRow[]>([]);
  const [categoryManagerDeleteTarget, setCategoryManagerDeleteTarget] = useState<CategoryManagerDraftRow | null>(null);
  const [categoryManagerError, setCategoryManagerError] = useState<{ title: string; message: string } | null>(null);
  const [editingCategory, setEditingCategory] = useState<MessageCategory | null>(null);
  const [discardCategoryAction, setDiscardCategoryAction] = useState<(() => void) | null>(null);
  const [categorySaving, setCategorySaving] = useState(false);
  const [newCategoryName, setNewCategoryName] = useState('');
  const [newCategoryHex, setNewCategoryHex] = useState<string | null | undefined>(undefined);
  const [newCategoryColor, setNewCategoryColor] = useState<MessageCategoryColor>('sky');
  const listRef = useRef<HTMLDivElement>(null);
  const didRestorePreferencesRef = useRef(false);
  const fetchRevision = useRef(0);
  const messageCheckpoint = useRef<string | null>(null);
  const pendingFetches = useRef(0);
  const confirmedSyncState = useRef<SyncState | null>(null);
  const syncedCategories = useRef<MessageCategory[]>([]);
  const categoryWritePending = useRef(false);
  const categoryDragPending = useRef(false);
  const managerBaseline = useRef(new Map<string, MessageCategory>());
  useEffect(() => { categoryWritePending.current = categorySaving; }, [categorySaving]);

  const { userId, token, logout, email, plan, accessStatus, refreshAccessStatus } = useAuth();
  const { t } = useTranslation();

  const fetchData = async (scrollToBottom = false, state?: SyncState) => {
    const scrollVersion = scrollRevision.current;
    const revision = ++fetchRevision.current;
    const previousState = confirmedSyncState.current;
    const reset = state && previousState && (state.latestMessage ?? '') < (previousState.latestMessage ?? '');
    const incremental = messageCheckpoint.current !== null && !reset;
    const recordsChanged = !state || !previousState || state.messages !== previousState.messages;
    const categoriesChanged = !state || !previousState || state.categories !== previousState.categories;
    const checkpoint = messageCheckpoint.current;
    const token = localStorage.getItem('authToken');
    pendingFetches.current += 1;
    try {
      const [messagesRes, categoriesRes] = await Promise.all([
        recordsChanged ? (incremental ? api.listMessageChanges(messageChangesSince(checkpoint!)) : api.listMessages(!state && checkpoint === null)) : Promise.resolve({ messages: [] }),
        categoriesChanged ? api.listMessageCategories(!state && checkpoint === null) : Promise.resolve({ categories: syncedCategories.current }),
      ]);

      if (revision !== fetchRevision.current || token !== localStorage.getItem('authToken') || categoryDragPending.current) return false;
      const nextCheckpoint = nextMessageCheckpoint(reset ? null : checkpoint, messagesRes.messages);
      setMessages(current => {
        const merged = mergeMessageChanges(incremental ? current : [], messagesRes.messages);
        return incremental && merged === current ? current : sortMessages(merged);
      });
      messageCheckpoint.current = nextCheckpoint;
      syncedCategories.current = categoriesRes.categories;
      if (categoriesChanged) setCategories(categoriesRes.categories);
      if (!state || !previousState || state.access !== previousState.access) {
        if (await refreshAccessStatus() === false) return false;
      }
      if (revision !== fetchRevision.current || token !== localStorage.getItem('authToken')) return false;
      if (state) confirmedSyncState.current = state;

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
      } else {
        const exists = (id: string | null) => categoriesRes.categories.some(category => category.id === id);
        setSelectedCategoryId(current => current === ALL_CATEGORY_ID || exists(current) ? current : (defaultCategory?.id ?? ALL_CATEGORY_ID));
        setDefaultSendCategoryId(current => exists(current) ? current : (defaultCategory?.id ?? null));
      }

      setCollectionCategory(current => current === ALL_CATEGORY_ID || categoriesRes.categories.some(c => c.id === current) ? current : ALL_CATEGORY_ID);
      if (scrollToBottom) {
        requestAnimationFrame(() => {
          if (listRef.current && scrollVersion === scrollRevision.current && !searchNavigation.current) {
            listRef.current.scrollTop = collectionsViewRef.current ? 0 : listRef.current.scrollHeight;
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
    messageCheckpoint.current = null;
    setMessages([]); setShowSearch(false); setSearchTarget(null); setSearchQuery('');
    searchNavigation.current = false; ++scrollRevision.current;
    confirmedSyncState.current = null;
    syncedCategories.current = [];
    void fetchData(true);
    let subscription: ReturnType<typeof createChangeNotifications> | undefined;
    const check = async () => {
      if (document.hidden) return true;
      if (pendingFetches.current || categoryWritePending.current || categoryDragPending.current) return false;
      const state = await api.getSyncState();
      if (token !== localStorage.getItem('authToken')) return true;
      if (pendingFetches.current || categoryWritePending.current || categoryDragPending.current) return false;
      const previous = confirmedSyncState.current;
      if (previous && previous.messages === state.messages && previous.categories === state.categories && previous.access === state.access) return true;
      return fetchData(false, state);
    };
    const start = () => {
      subscription?.stop(); subscription = undefined;
      if (!document.hidden && token) subscription = createChangeNotifications({
        token, onChange: check, stream: !window.syncaDesktop,
        onUnauthorized: () => { void api.getSyncState().catch(() => {}); },
      });
    };
    start();
    const unsubscribe = window.syncaDesktop?.subscribe('refresh', () => subscription?.hint());
    document.addEventListener('visibilitychange', start);
    window.addEventListener('online', start);
    return () => {
      ++fetchRevision.current;
      subscription?.stop(); unsubscribe?.();
      document.removeEventListener('visibilitychange', start);
      window.removeEventListener('online', start);
    };
  }, [email, token]);

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
  const selectedScopeIsAll = !showScratchpad && !showCollections && selectedCategoryId === ALL_CATEGORY_ID;
  const selectedCategory = showCollections ? undefined : categories.find(category => category.id === selectedCategoryId);
  const heading = showScratchpad ? t('scratch.title') : showCollections ? t('collections.title') : selectedScopeIsAll ? t('common.all') : selectedCategory?.isDefault ? t('message_category.default_badge') : selectedCategory?.name;
  const activeSendCategoryId = showCollections ? (collectionCategory === ALL_CATEGORY_ID ? defaultCategory?.id : collectionCategory) : selectedScopeIsAll ? effectiveDefaultSendCategoryId : selectedCategoryId;

  const filteredMessages = useMemo(() => recordsInArea(messages, showCollections,
    (showCollections ? collectionCategory : selectedCategoryId) === ALL_CATEGORY_ID ? undefined : (showCollections ? collectionCategory : selectedCategoryId)),
    [messages, showCollections, collectionCategory, selectedCategoryId]);
  const counts = useMemo(() => taskCounts(messages), [messages]);
  const todoCountByCategoryId = counts.categories;
  const allTodoCount = counts.total;
  const visibleSingleModeCategories = useMemo(() => categories, [categories]);
  const [syncSequence, setSyncSequence] = useState(0);
  const handleRefresh = async () => {
    // Keep in-flight category edits/order and concurrent sync responses authoritative.
    if (pendingFetches.current || categoryWritePending.current || categoryDragPending.current) return;
    if (!await fetchData(false)) return;
    if (compact) { setToastMsg(t('message_list.sync_success', 'Synced')); setShowToast(true); }
    else setSyncSequence(value => value + 1);
  };

  const refreshRef = useRef(handleRefresh);
  useLayoutEffect(() => { refreshRef.current = handleRefresh; });
  useEffect(() => {
    const refresh = () => { void refreshRef.current(); };
    const shortcut = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'r' && !event.altKey && !event.shiftKey) {
        event.preventDefault();
        if (!event.isComposing && event.keyCode !== 229) refresh();
      }
    };
    window.addEventListener('keydown', shortcut);
    const unsubscribe = window.syncaDesktop?.subscribe('sync', refresh);
    return () => { window.removeEventListener('keydown', shortcut); unsubscribe?.(); };
  }, []);

  const buildCategoryManagerRows = () =>
    categories
      .map((category) => ({
        clientId: category.id,
        id: category.id,
        name: category.name,
        color: category.color,
        colorHex: category.colorHex,
        isDefault: category.isDefault,
      }));

  const settingsSurface = React.useContext(SettingsSurface);
  const priorAction = useRef(settingsSurface?.action);
  useEffect(() => {
    if (priorAction.current && !settingsSurface?.host) {
      setPanel(null); setShowAI(false); setShowCategoryModal(false);
      settingsSurface?.finish();
    }
    priorAction.current = settingsSurface?.action;
  }, [settingsSurface?.host, settingsSurface?.action]);
  function finishManager() { setShowCategoryModal(false); if (settingsSurface?.action === 'categories') settingsSurface.finish(); }
  const openCategoryManager = () => {
    setManagerInvalid(null); setManagerEditing(false);
    managerBaseline.current = new Map(categories.map(category => [category.id,category]));
    setCategoryManagerRows(buildCategoryManagerRows());
    setCategoryManagerEditor(null);
    setCategoryManagerDeleteTarget(null);
    setCategoryManagerError(null);
    setShowCategoryModal(true);
  };

  useEffect(() => {
    const show = (event: Event) => {
      switch ((event as CustomEvent).detail) {
        case 'categories': openCategoryManager(); break;
        case 'ai': setShowAI(true); break;
        case 'feedback': setPanel('feedback'); break;
      }
    };
    window.addEventListener('synca-settings-action', show);
    return () => window.removeEventListener('synca-settings-action', show);
  }, [categories]);

  useEffect(() => {
    if (!showCategoryModal) return;
    const previous = managerBaseline.current;
    setCategoryManagerRows(rows => categories.map(category => {
      const draft = rows.find(row => row.id === category.id), baseline = previous.get(category.id);
      if (!draft || !baseline) return {...category,clientId:category.id};
      const nameDirty = draft.name !== baseline.name;
      const colorDirty = draft.color !== baseline.color || draft.colorHex !== baseline.colorHex;
      return {...draft,...category,name:nameDirty ? draft.name : category.name,color:colorDirty ? draft.color : category.color,colorHex:colorDirty ? draft.colorHex : category.colorHex};
    }));
    managerBaseline.current = new Map(categories.map(category => [category.id,category]));
  }, [categories,showCategoryModal]);

  function validateManagerName(row: CategoryManagerDraftRow) {
    if (row.isDefault) return true;
    const name = row.name.trim().toLocaleLowerCase();
    const duplicate = categoryManagerRows.some(item => item.clientId !== row.clientId && item.name.trim().toLocaleLowerCase() === name);
    if (name && !duplicate) return true;
    settingsSurface?.continueEditing();
    setManagerInvalid({ id: row.clientId, message: t(name ? 'review.action.duplicate' : 'message_category.invalid_message') });
    managerNames.current.get(row.clientId)?.focus();
    return false;
  }

  const saveCategoryRow = async (row: CategoryManagerDraftRow, patch: Partial<Pick<MessageCategory, 'name' | 'color' | 'colorHex'>>) => {
    if (!row.id || categoryWritePending.current || (patch.name !== undefined && !validateManagerName(row))) return;
    if (patch.name !== undefined) { const name = patch.name.trim(); if (!name || name === categories.find(c => c.id === row.id)?.name) return; patch = {...patch,name}; }
    ++fetchRevision.current; categoryWritePending.current = true; setCategorySaving(true);
    try {
      const updated = await api.updateMessageCategory(row.id, patch);
      setCategoryManagerRows(rows => rows.map(item => item.id === updated.id ? {...item,...(patch.name !== undefined ? {name:updated.name} : {}),...(patch.color !== undefined || patch.colorHex !== undefined ? {color:updated.color,colorHex:updated.colorHex} : {})} : item));
      setCategories(current => current.map(item => item.id === updated.id ? updated : item));
      await fetchData(false);
    } catch { setCategoryManagerError({title:t('common.error'),message:t('navigation.save_failed')}); }
    finally { categoryWritePending.current = false; setCategorySaving(false); }
  };
  const reorderManager = async (next: CategoryManagerDraftRow[]) => {
    if (categoryWritePending.current) return;
    if (!next.every(validateManagerName)) return;
    const previous = categoryManagerRows; setCategoryManagerRows(next);
    if (next.some(row => !row.id)) return;
    ++fetchRevision.current; categoryWritePending.current = true; setCategorySaving(true);
    try {
      // Pointer sorting keeps an active name field focused. Flush its draft under
      // this same write lock, so blur and reorder cannot race or lose either edit.
      const renamed = new Map<string, MessageCategory>();
      for (const row of next) {
        const saved = categories.find(category => category.id === row.id);
        if (!row.isDefault && row.name.trim() && saved && row.name.trim() !== saved.name) {
          renamed.set(saved.id, await api.updateMessageCategory(saved.id, { name: row.name.trim() }));
        }
      }
      await api.reorderMessageCategories(next.filter(row => !row.isDefault).map(row => row.id!));
      setCategories(current => current.map(category => renamed.get(category.id) ?? category).sort((a,b) => next.findIndex(row => row.id === a.id) - next.findIndex(row => row.id === b.id)));
    }
    catch { setCategoryManagerRows(previous); setCategoryManagerError({title:t('common.error'),message:t('navigation.save_failed')}); }
    finally { categoryWritePending.current = false; setCategorySaving(false); }
  };
  const moveCategoryManagerRow = (index: number, direction: -1 | 1) => {
    const targetIndex = index + direction;
    if (index < 1 || targetIndex < 1 || index >= categoryManagerRows.length || targetIndex >= categoryManagerRows.length) return;
    const next = [...categoryManagerRows]; next.splice(targetIndex,0,next.splice(index,1)[0]); void reorderManager(next);
  };

  const editCategoryManagerRow = (row?: CategoryManagerDraftRow) => {
    setCategoryManagerEditor(row ?? { clientId: crypto.randomUUID(), name: '', color: 'sky' });
    setEditingCategory(null);
    setNewCategoryName(row?.name ?? '');
    setNewCategoryHex(row?.colorHex);
    setNewCategoryColor(row?.color ?? 'sky');
    setShowCreateCategoryModal(true);
  };

  const closeCategoryEditor = () => {
    setShowCreateCategoryModal(false);
    setCategoryManagerEditor(null);
  };

  const handleScopedClear = async (categoryId?: string | null) => {
    if (clearing) return;
    setClearing(true); setClearError(false);
    try {
      await api.deleteCompletedMessages(categoryId ?? null);
      setShowClearModal(false);
      await fetchData(false);
    } catch {
      setClearError(true);
    } finally { setClearing(false); }
  };

  const handleCreateCategory = async () => {
    const trimmedName = newCategoryName.trim();
    if (!trimmedName || categorySaving) return;
    if (categoryManagerEditor) {
      const duplicated = !categoryManagerEditor.isDefault && categoryManagerRows.some(row => row.clientId !== categoryManagerEditor.clientId && row.name.trim().toLocaleLowerCase() === trimmedName.toLocaleLowerCase());
      if (duplicated) { setDuplicateName(true); categoryNameInput.current?.focus(); return; }
      const patch = categoryEditPatch(categoryManagerEditor, { name: trimmedName, color: newCategoryColor, colorHex: newCategoryHex });
      if (categoryManagerEditor.id && !patch) { closeCategoryEditor(); return; }
      ++fetchRevision.current; categoryWritePending.current = true; setCategorySaving(true);
      try {
        const saved = categoryManagerEditor.id ? await api.updateMessageCategory(categoryManagerEditor.id, patch!) : await api.createMessageCategory(trimmedName,newCategoryColor,newCategoryHex);
        const updated = { ...categoryManagerEditor, ...saved, colorHex:saved.colorHex };
        setCategoryManagerRows(rows => rows.some(row => row.clientId === updated.clientId) ? rows.map(row => row.clientId === updated.clientId ? updated : row) : [...rows, updated]);
        setCategories(current => current.some(row => row.id === saved.id) ? current.map(row => row.id === saved.id ? saved : row) : [...current,saved]);
        setShowCreateCategoryModal(false); setCategoryManagerEditor(null);
      } catch { setCategoryManagerError({title:t('common.error'),message:t('navigation.save_failed')}); }
      finally { categoryWritePending.current = false; setCategorySaving(false); }
      return;
    }
    const duplicated = !editingCategory?.isDefault && categories.some((category) => category.id !== editingCategory?.id && category.name.trim().toLocaleLowerCase() === trimmedName.toLocaleLowerCase());
    if (duplicated) {
      setDuplicateName(true); categoryNameInput.current?.focus();
      return;
    }
    const patch = editingCategory ? categoryEditPatch(editingCategory, { name: trimmedName, color: newCategoryColor, colorHex: newCategoryHex }) : null;
    if (editingCategory && !patch) { setEditingCategory(null); closeCategoryEditor(); return; }
    setCategorySaving(true);
    try {
      if (editingCategory) await api.updateMessageCategory(editingCategory.id, patch!);
      else await api.createMessageCategory(trimmedName, newCategoryColor, newCategoryHex);
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
    if (categorySaving) return;
    if (!categoryManagerRows.every(validateManagerName)) return;

    const baselineById = managerBaseline.current;
    ++fetchRevision.current; categoryWritePending.current = true; setCategorySaving(true);
    try {
      // Read current server membership; a draft's absence never means deletion.
      const latest = await api.listMessageCategories();
      const originalById = new Map(latest.categories.map(category => [category.id,category]));
      setCategories(latest.categories);
      for (const row of categoryManagerRows) {
        const name = row.name.trim();
        if (!row.id) {
          const created = await api.createMessageCategory(name, row.color, row.colorHex);
          setCategoryManagerRows(rows => rows.map(item => item.clientId === row.clientId ? { ...item, ...created, colorHex: created.colorHex } : item));
          setCategories(current => [...current, created]);
          continue;
        }

        const original = originalById.get(row.id);
        const baseline = baselineById.get(row.id);
        if (!original || !baseline) continue;
        const patch: Partial<Pick<MessageCategory, 'name' | 'color' | 'colorHex'>> = {};
        if (!original.isDefault && name !== baseline.name) patch.name = name;
        if (row.color !== baseline.color || row.colorHex !== baseline.colorHex) { patch.color = row.color; patch.colorHex = row.colorHex; }
        if (Object.keys(patch).length > 0) {
          const updated = await api.updateMessageCategory(row.id, patch);
          setCategoryManagerRows(rows => rows.map(item => item.id === updated.id ? { ...item, ...updated, colorHex: updated.colorHex } : item));
          setCategories(current => current.map(item => item.id === updated.id ? updated : item));
        }
      }

      finishManager();
      await fetchData(false);
    } catch (error) {
      console.error(error);
      setCategoryManagerError({ title: t('common.error'), message: t('navigation.save_failed') });
    } finally { setCategorySaving(false); }
  };

  const reorderSidebar = async (source: string, target: string) => {
    if (categoryWritePending.current || source === target) return;
    const previous = categories; const custom = categories.filter(c => !c.isDefault);
    const from = custom.findIndex(c => c.id === source), to = custom.findIndex(c => c.id === target);
    if (from < 0 || to < 0) return;
    custom.splice(to,0,custom.splice(from,1)[0]); setCategories([...categories.filter(c => c.isDefault),...custom]); ++fetchRevision.current; categoryWritePending.current = true; setCategorySaving(true);
    try { await api.reorderMessageCategories(custom.map(c => c.id)); }
    catch { setCategories(previous); setCategoryManagerError({title:t('common.error'),message:t('navigation.save_failed')}); }
    finally { categoryWritePending.current = false; setCategorySaving(false); }
  };

  const sortLifecycle = {
    disabled: categorySaving,
    onStart: () => { categoryDragPending.current = true; ++fetchRevision.current; },
    onEnd: () => { categoryDragPending.current = false; },
  };
  const sidebarSort = usePointerSort({ ...sortLifecycle, onCommit: (source, target) => { void reorderSidebar(source, target); } });
  const managerSort = usePointerSort({ ...sortLifecycle, onCommit: (source, target) => {
    const from = categoryManagerRows.findIndex(row => row.clientId === source);
    const to = categoryManagerRows.findIndex(row => row.clientId === target);
    if (from > 0 && to > 0) void reorderManager(moveItem(categoryManagerRows, from, to));
  } });

  const activateCategory = (id: string) => {
    setShowScratchpad(false);
    setShowCollections(false);
    setDrawerOpen(false);
    setSearchTarget(null); searchNavigation.current = false; ++scrollRevision.current;
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
    setSearchTarget(null); searchNavigation.current = false; ++scrollRevision.current;
    setShowScratchpad(false);
    setShowCollections(false);
    setSelectedCategoryId(buttons[next].dataset.categoryId!);
  };

  const fetchDataRef = useRef(fetchData);
  useLayoutEffect(() => { fetchDataRef.current = fetchData; });
  const updateMessageList = useCallback(() => { void fetchDataRef.current(false); }, []);
  const applySavedText = useCallback((updated: SyncaMessage) => {
    ++fetchRevision.current;
    setMessages(current => sortMessages(current.map(item => item.id === updated.id && Date.parse(updated.updatedAt) >= Date.parse(item.updatedAt) ? updated : item)));
    void fetchDataRef.current(false);
  }, []);
  const editMessage = useCallback((message: SyncaMessage) => setEditingMessage({ ...message }), []);

  useEffect(() => {
    const shortcut = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'f' && !event.altKey) {
        const searchInput = document.querySelector<HTMLInputElement>('.message-search-field input');
        if (searchInput) { event.preventDefault(); searchInput.focus(); return; }
        if (document.querySelector('[role="dialog"]')) return;
        event.preventDefault(); setShowSearch(true);
      }
    };
    window.addEventListener('keydown', shortcut);
    return () => window.removeEventListener('keydown', shortcut);
  }, []);
  useLayoutEffect(() => {
    if (!searchTarget || !listRef.current) return;
    return revealSearchTarget(listRef.current, searchTarget.id, () => {
      setToastMsg(t('search.unavailable')); setShowToast(true);
    }, searchTarget.matchedText);
  }, [searchTarget, t]);
  const selectSearchResult = (id: string, matchedText?: string) => {
    const live = messages.find(message => message.id === id && !message.isDeleted);
    if (!live) { setToastMsg(t('search.unavailable')); setShowToast(true); return false; }
    ++scrollRevision.current; searchNavigation.current = true;
    setShowScratchpad(false);
    setShowCollections(Boolean(live.collectedAt));
    if (live.collectedAt) setCollectionCategory(ALL_CATEGORY_ID);
    setSelectedCategoryId(categories.some(category => category.id === live.categoryId) ? live.categoryId! : ALL_CATEGORY_ID);
    setShowSearch(false); setSearchTarget({ id, matchedText, nonce: Date.now() });
    return true;
  };

  const menuCategory = categories.find(category => category.id === categoryMenu?.id);
  const customCategories = categories.filter(category => !category.isDefault);
  const menuIndex = customCategories.findIndex(category => category.id === menuCategory?.id);

  const completed = filteredMessages.filter((message) => message.isCleared && !message.isDeleted);
  const pending = filteredMessages.filter((message) => !message.isCleared);

  const clearComposing = useRef(false);
  const requestClearCompleted = useCallback(() => {
    if (!completed.length || clearing || clearComposing.current || document.querySelector('[role="dialog"]')) return;
    setClearError(false);
    setShowClearModal(true);
  }, [completed.length, clearing]);

  useEffect(() => {
    const desktop = window.syncaDesktop;
    const clear = desktopClearShortcut(desktop?.platform);
    if (!desktop || !clear) return;
    const shortcut = (event: KeyboardEvent) => {
      if (event.key !== clear.key || !event.shiftKey || event.altKey ||
          (clear.mac ? !event.metaKey || event.ctrlKey : !event.ctrlKey || event.metaKey)) return;
      if (event.isComposing || event.keyCode === 229 || clearComposing.current) return;
      // Consume repeated presses even while the confirmation is open: never edit the draft.
      event.preventDefault();
      if (!event.repeat) requestClearCompleted();
    };
    const compositionStart = () => { clearComposing.current = true; };
    const compositionEnd = () => { clearComposing.current = false; };
    const unsubscribe = desktop.subscribe('clear-completed', requestClearCompleted);
    window.addEventListener('keydown', shortcut);
    window.addEventListener('compositionstart', compositionStart);
    window.addEventListener('compositionend', compositionEnd);
    window.addEventListener('blur', compositionEnd);
    return () => {
      unsubscribe();
      window.removeEventListener('keydown', shortcut);
      window.removeEventListener('compositionstart', compositionStart);
      window.removeEventListener('compositionend', compositionEnd);
      window.removeEventListener('blur', compositionEnd);
    };
  }, [requestClearCompleted]);

  useEffect(() => {
    window.syncaDesktop?.clearCompletedAvailable?.(completed.length > 0 && !clearing);
    return () => window.syncaDesktop?.clearCompletedAvailable?.(false);
  }, [completed.length, clearing]);

  const sidebar=(
      <SidebarFrame>
        <div className="sidebar-brand"><img src="/logo.png?v=a2" alt="" /><span>Synca</span>{compact && <button type="button" className="close-categories" aria-label={t('navigation.close')} onClick={()=>setDrawerOpen(false)}><X size={18}/></button>}</div>

        <div className="category-toolbar">
          <div className="category-switcher" ref={sidebarSort.containerRef}>
            <button className={`category-chip has-badge ${selectedScopeIsAll ? 'active' : ''} category-all`} aria-pressed={selectedScopeIsAll} data-category-id={ALL_CATEGORY_ID} onKeyDown={navigateCategories} onClick={() => activateCategory(ALL_CATEGORY_ID)}>
              <LayoutGrid size={16} aria-hidden="true" />{t('common.all', 'All')}
              <CategoryTodoBadge count={allTodoCount} />
            </button>
            <button className={`category-chip ${showScratchpad ? 'active' : ''}`} aria-pressed={showScratchpad} onClick={()=>{setShowScratchpad(true);setDrawerOpen(false);}}><FileText size={16} aria-hidden="true"/>{t('scratch.title')}</button>
            <button className={`category-chip ${!showScratchpad && showCollections ? 'active' : ''}`} aria-pressed={!showScratchpad && showCollections} onClick={() => { setShowScratchpad(false); setShowCollections(true); setDrawerOpen(false); setSearchTarget(null); }}><Bookmark size={16} aria-hidden="true"/>{t('collections.title')}</button>
            <div className="category-section-heading">
              <span>{t('message_category.section_title')}</span>
              <button type="button" onClick={()=>{setDrawerOpen(false);openSettings('categories')}} aria-label={t('message_list.manage_categories')} title={t('message_list.manage_categories')}>
                <Tags size={16} aria-hidden="true" />
              </button>
            </div>
            {visibleSingleModeCategories.map((category) => (
              <button
                key={category.id}
                className={`category-chip has-badge color-${category.color} ${!showScratchpad && !showCollections && selectedCategoryId === category.id ? 'active' : ''}`}
                data-category-id={category.id}
                aria-pressed={!showScratchpad && !showCollections && selectedCategoryId === category.id}
                onContextMenu={event => { event.preventDefault(); setCategoryMenu({ id: category.id, x: event.clientX, y: event.clientY, trigger: event.currentTarget }); }}
                onClick={() => activateCategory(category.id)}
                onDoubleClick={() => { setEditingCategory(category); setNewCategoryHex(category.colorHex); setNewCategoryName(category.name); setNewCategoryColor(category.color); setShowCreateCategoryModal(true); }}
                style={categoryStyle(category.colorHex, category.color)}
                data-sort-id={category.isDefault ? undefined : category.id} onPointerDown={e => { if (!category.isDefault) sidebarSort.begin(e, category.id); }} draggable={false}

                onKeyDown={e => { if(e.key === 'ContextMenu' || (e.shiftKey && e.key === 'F10')) { e.preventDefault(); const rect=e.currentTarget.getBoundingClientRect(); setCategoryMenu({id:category.id,x:rect.left+12,y:rect.bottom,trigger:e.currentTarget}); return; } if(e.altKey && ['ArrowUp','ArrowDown'].includes(e.key)) { e.preventDefault(); const custom=categories.filter(c => !c.isDefault); const target=custom[custom.findIndex(c => c.id === category.id)+(e.key === 'ArrowUp' ? -1 : 1)]; if(target) void reorderSidebar(category.id,target.id); return; } navigateCategories(e); if (e.key === 'F2') { e.preventDefault(); setEditingCategory(category); setNewCategoryHex(category.colorHex); setNewCategoryName(category.name); setNewCategoryColor(category.color); setShowCreateCategoryModal(true); } }}
              >
                <span className="category-name" title={category.isDefault ? undefined : category.name}>
                  {category.isDefault ? t('message_category.default_badge', 'Default') : category.name}
                </span>
                <CategoryTodoBadge count={todoCountByCategoryId[category.id] ?? 0} />
              </button>
            ))}
            <button className="category-add-btn" aria-label={t('message_category.add_action')} onClick={() => { setDrawerOpen(false); setEditingCategory(null); setNewCategoryHex(undefined); setNewCategoryName(''); setNewCategoryColor('sky'); setShowCreateCategoryModal(true); }} title={t('message_category.new_section')}>
              <Plus size={18} aria-hidden="true" />
            </button>
          </div>

        </div>
      <FunctionMenu onAI={() => setShowAI(true)} email={email} planLabel={t(!accessStatus ? 'message_list.loading' : accessStatus.isUnlimited ? 'access.purchased_lifetime' : 'access.free_title')}
        usage={plan === 'free' && accessStatus ? { used: accessStatus.todayUsed, limit: accessStatus.todayLimit ?? 20 } : null}
        onAccount={() => openSettings('account')} onSettings={() => {setDrawerOpen(false);openSettings()}} onCategories={openCategoryManager}
        onFeedback={() => openSettings('feedback')} onAbout={() => openSettings('about')} onLogout={() => setShowLogoutModal(true)} />
      </SidebarFrame>
  );
  return (
    <div className="app-container calm-shell">
      {panel && <ShellPanel kind={panel} email={email} onClose={() => {setPanel(null); if(settingsSurface?.action==='feedback') settingsSurface.finish();}} onLogout={() => { setPanel(null); setShowLogoutModal(true); }} />}
      {categoryMenu && menuCategory && <CategoryContextMenu anchor={categoryMenu} name={menuCategory.name}
        protectedCategory={menuCategory.isDefault} busy={categorySaving}
        canMoveUp={menuIndex > 0} canMoveDown={menuIndex >= 0 && menuIndex < customCategories.length - 1}
        onClose={() => setCategoryMenu(null)}
        onEdit={() => { setCategoryManagerEditor(null); setEditingCategory(menuCategory); setNewCategoryHex(menuCategory.colorHex); setNewCategoryName(menuCategory.name); setNewCategoryColor(menuCategory.color); setShowCreateCategoryModal(true); }}
        onMove={direction => { const target = customCategories[menuIndex + direction]; if (menuIndex >= 0 && target) void reorderSidebar(menuCategory.id, target.id); }}
        onDelete={() => setCategoryManagerDeleteTarget({ ...menuCategory, clientId: menuCategory.id })} />}
      {compact ? <MobileCategoryDrawer open={drawerOpen} onClose={()=>setDrawerOpen(false)}>{sidebar}</MobileCategoryDrawer> : sidebar}
      <main className="calm-main">
        <UpdateNotice/>
        <header className="header">
          {!compact && <SyncFeedback sequence={syncSequence} label={t('message_list.sync_success', 'Synced')}/>}
          {compact ? <button type="button" className="mobile-category-trigger" onClick={()=>setDrawerOpen(true)} aria-haspopup="dialog" aria-expanded={drawerOpen} aria-label={t('message_category.section_title')+' · '+heading+(showScratchpad || showCollections ? '' : ' · '+pending.length)}>
            <PanelLeft size={19}/>{selectedCategory && <i style={categoryStyle(selectedCategory.colorHex,selectedCategory.color)} />}<strong>{heading}</strong>{!showScratchpad && !showCollections && <span>{pending.length}</span>}
          </button> : <div className="stream-heading"><h1 title={heading}>{heading}</h1>
          {!showScratchpad && !showCollections && <p>{t('preferences.pending_count', { count: pending.length })}<span aria-hidden="true"> · </span>{t('preferences.completed_count', { count: completed.length })}</p>}</div>}
          <div className="header-actions">
            <button className="header-btn search-trigger" data-pointer-opened={searchPointerOpened} onPointerDown={() => setSearchPointerOpened(true)} onKeyDown={() => setSearchPointerOpened(false)} onClick={() => setShowSearch(true)} aria-label={t('search.title')} title={t('search.title')} aria-keyshortcuts="Meta+f Control+f"><Search size={18} strokeWidth={1.7} /></button>
            <button className="header-btn" onClick={() => void handleRefresh()} aria-label={t('navigation.sync')} title={t('navigation.sync')} aria-keyshortcuts="Meta+r Control+r"><RotateCw size={18} strokeWidth={1.7} /></button>
            {!showScratchpad && !showCollections && <button className="header-btn" disabled={!completed.length || clearing} onClick={requestClearCompleted} aria-label={t('message_list.clear_completed')} aria-keyshortcuts={desktopClearShortcut(window.syncaDesktop?.platform)?.aria} title={t('message_list.clear_completed') + (desktopClearShortcut(window.syncaDesktop?.platform) ? ` · ${desktopClearShortcut(window.syncaDesktop?.platform)!.keys.join(' ')}` : '')}><BroomIcon size={18} /></button>}
          </div>
        </header>
        {showScratchpad ? (userId ? <Scratchpad key={userId} account={userId}/> : <AppLoading/>) : <>
        {showCollections && <div className="collection-filter"><label>{t('collections.category')} <select value={collectionCategory} onChange={e=>{setCollectionCategory(e.target.value);setSearchTarget(null);}}>
          <option value={ALL_CATEGORY_ID}>{t('collections.all')}</option>{categories.map(category=><option key={category.id} value={category.id}>{category.isDefault?t('message_category.default_badge'):category.name}</option>)}
        </select></label><span>{t('collections.save_to', {name: categories.find(c=>c.id===activeSendCategoryId)?.isDefault ? t('message_category.default_badge') : categories.find(c=>c.id===activeSendCategoryId)?.name})}</span></div>}
          <div className="message-list" ref={listRef}>
            {isLoading && messages.length === 0 && <AppLoading overlay />}

            {!isLoading && filteredMessages.length === 0 && (
              showCollections ? <div className="empty-state"><Bookmark size={48} aria-hidden="true"/><h2>{t('collections.empty')}</h2><p>{t('collections.empty_detail')}</p></div> : <EmptyMessageState />
            )}

            {filteredMessages.length > 0 && (
              <>
                {completed.map((message) => (
                  <MessageBubble key={message.id} showsSeparator={message.id !== (pending.at(-1)?.id ?? completed.at(-1)?.id)} message={message} categories={categories} onEdit={editMessage} onTextSaved={applySavedText} onUpdate={updateMessageList} />
                ))}

                {!showCollections && pending.length > 0 && (
                  <div style={{ marginTop: '8px', marginBottom: '4px' }}>
                    <span style={{ fontSize: '12px', fontWeight: 'bold', color: 'var(--text-secondary)', background: 'var(--border-color)', padding: '2px 8px', borderRadius: '4px' }}>
                      {t('message_list.todo_section', 'Inbox')}
                    </span>
                  </div>
                )}

                {pending.map((message) => (
                  <MessageBubble key={message.id} showsSeparator={message.id !== (pending.at(-1)?.id ?? completed.at(-1)?.id)} message={message} categories={categories} onEdit={editMessage} onTextSaved={applySavedText} onUpdate={updateMessageList} />
                ))}
              </>
            )}
          </div>

          <InputBar key={token} isCollected={showCollections} availableScopeIds={window.syncaDesktop ? undefined : [ALL_CATEGORY_ID, ...categories.map(category => category.id), `collection:${ALL_CATEGORY_ID}`, ...categories.map(category => `collection:${category.id}`)]} fallbackScopeId={defaultCategory?.id} scopeId={showCollections ? `collection:${collectionCategory}` : selectedCategoryId} focusRequest={composerFocusRequest} categoryId={activeSendCategoryId} onSent={() => { setSearchTarget(null); searchNavigation.current = false; void fetchData(true); }} />
        </>}
      </main>

      {showSearch && <MessageSearch key={email} query={searchQuery} onQueryChange={setSearchQuery} messages={messages} categories={categories} currentCategoryId={undefined} onCancel={() => setShowSearch(false)} onSelect={selectSearchResult} />}

      {editingMessage && <MessageTextEditor key={editingMessage.id} message={editingMessage}
        onCancel={() => setEditingMessage(null)} onSaved={updated => {
          setEditingMessage(null);
          applySavedText(updated);
          setToastMsg(t('message_edit.saved')); setShowToast(true);
        }} />}

      <Toast message={toastMsg} visible={showToast} onClose={() => setShowToast(false)} />

      {showAI && <Modal title={t('ai.connect')} message="" size="large" className="ai-management-modal" scrollBody hideActions onCancel={() => {setShowAI(false); if(settingsSurface?.action==='ai') settingsSurface.finish();}} onConfirm={() => {setShowAI(false); if(settingsSurface?.action==='ai') settingsSurface.finish();}}><AIPage presentation="dialog" /></Modal>}

      {showLogoutModal && (
        <Modal
          className="logout-confirm-modal"
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
          title={t(selectedScopeIsAll ? 'review.action.clear_all' : 'review.action.clear_category', { count: completed.length, name: heading })}
          message={clearError ? t('review.action.clear_failed') : ''}
          confirmText={t('review.action.clear_count', { count: completed.length })}
          confirmDisabled={clearing || !completed.length} cancelDisabled={clearing} closeDisabled={clearing}
          cancelText={t('common.cancel')}
          onConfirm={() => void handleScopedClear(selectedScopeIsAll ? null : selectedCategoryId)}
          onCancel={() => { if (!clearing) setShowClearModal(false); }}
          destructive
        />
      )}

      {showCategoryModal && (
        <Modal size="standard" className="category-manager-modal"
          confirmDisabled={categorySaving} cancelDisabled={categorySaving} closeDisabled={categorySaving}
          title={t('message_list.manage_categories', 'Manage Categories')}
          closeLabel={t('navigation.close')}
          message=""
          hideActions={Boolean(settingsSurface?.host && settingsSurface.action === 'categories')}
          hideCancel confirmText={t('polish.done')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={() => void handleCategoryManagerSave()}
          onCancel={() => { if (categorySaving) return; if (JSON.stringify(categoryManagerRows) !== JSON.stringify(buildCategoryManagerRows())) void handleCategoryManagerSave(); else finishManager(); }}
        >
          <fieldset className="category-manager-content" disabled={categorySaving}>
            {compact && <div className="category-manager-tools">
              <button type="button" aria-pressed={managerEditing} onClick={() => setManagerEditing(value => !value)}>
                {t(managerEditing ? 'review.action.finish_editing' : 'review.action.edit')}
              </button>
            </div>}
            <div className="category-manager-scroll">
              <div className="category-manager-rows" ref={managerSort.containerRef}>
                {categoryManagerRows.map((row, index) => (
                  <div key={row.clientId} className="category-manager-row" data-sort-id={row.isDefault ? undefined : row.clientId}>
                    {compact ? <>
                      <span aria-hidden="true" className="category-manager-dot" style={categoryStyle(row.colorHex, row.color)} />
                      {managerEditing ? <button type="button" className="category-manager-mobile-name" onClick={() => editCategoryManagerRow(row)}>
                        {row.isDefault ? t('message_category.default_badge') : row.name}
                      </button> : <span className="category-manager-static-name">{row.isDefault ? t('message_category.default_badge') : row.name}</span>}
                    </> : <>
                      <CategoryPalette color={row.color} colorHex={row.colorHex} onChange={(color, colorHex) => { setCategoryManagerRows(rows => rows.map(item => item.clientId === row.clientId ? {...item,color,colorHex} : item)); void saveCategoryRow(row,{color,colorHex}); }} />
                      {row.isDefault ? <span className="category-manager-name category-name-readonly">{t('message_category.default_badge')}</span> : <input
                        className="category-manager-name" aria-label={t('message_category.edit_title')}
                        ref={el => { if (el) managerNames.current.set(row.clientId, el); else managerNames.current.delete(row.clientId); }}
                        aria-invalid={managerInvalid?.id === row.clientId || undefined}
                        aria-describedby={managerInvalid?.id === row.clientId ? 'category-manager-invalid' : undefined}
                        onBlur={() => window.setTimeout(() => { if (!categoryWritePending.current && managerNames.current.has(row.clientId)) void saveCategoryRow(row,{name:row.name}); }, 0)}
                        onKeyDown={event => { if (event.key === 'Enter' && !event.nativeEvent.isComposing && event.nativeEvent.keyCode !== 229) { event.preventDefault(); event.currentTarget.blur(); } }}
                        value={row.name} onChange={e => { setManagerInvalid(null); setCategoryManagerRows(rows => rows.map(item => item.clientId === row.clientId ? {...item,name:e.target.value} : item)); }} />}
                    </>}
                    {!row.isDefault && (!compact || managerEditing) && <div className="category-manager-row-actions">
                      <button type="button" className="category-sort-handle" aria-label={t('polish.reorder') + ' ' + row.name} onPointerDown={e => {
                        if (document.activeElement?.classList.contains('category-manager-name')) e.preventDefault();
                        managerSort.begin(e, row.clientId, true);
                      }} onKeyDown={e => { if(e.altKey && ['ArrowUp','ArrowDown'].includes(e.key)) { e.preventDefault(); moveCategoryManagerRow(index,e.key === 'ArrowUp' ? -1 : 1); } }}><GripVertical size={17}/></button>
                      <button type="button" className="category-manager-delete" onClick={() => {
                        const saved = categories.find(category => category.id === row.id);
                        if (saved) setCategoryManagerDeleteTarget({ ...saved, clientId: row.clientId });
                      }} aria-label={t('message_category.delete_action') + ' ' + row.name}><Trash2 size={17}/></button>
                    </div>}
                    {managerInvalid?.id === row.clientId && <p className="category-validation" id="category-manager-invalid" role="alert">{managerInvalid.message}</p>}
                  </div>
                ))}
              </div>
              <button type="button" className="category-manager-add" onClick={() => editCategoryManagerRow()}><Plus size={17} aria-hidden="true" />{t('message_category.new_section')}</button>
            </div>
          </fieldset>
        </Modal>
      )}

      {showCreateCategoryModal && (
        <Modal
          className="category-editor-modal"
          title={t((editingCategory || categoryManagerEditor?.name) ? 'message_category.edit_title' : 'message_category.new_section')}
          message=""
          confirmText={t((editingCategory || categoryManagerEditor?.name) ? 'common.save' : 'message_category.add_action')}
          confirmDisabled={categorySaving || !newCategoryName.trim()} closeDisabled={categorySaving} cancelDisabled={categorySaving}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={() => void handleCreateCategory()}
          onCancel={() => { if (categorySaving) return; const original = categoryManagerEditor ?? editingCategory; const changed = original ? newCategoryName !== original.name || newCategoryColor !== original.color || newCategoryHex !== original.colorHex : !!newCategoryName.trim() || newCategoryColor !== 'sky'; if (changed) setDiscardCategoryAction(() => () => closeCategoryEditor()); else closeCategoryEditor(); }}
          size="compact"
        >
          <div className="category-create-stack">
            {(editingCategory?.isDefault || categoryManagerEditor?.isDefault) ? <div className="category-name-input category-name-readonly">{t('message_category.default_badge')}</div> : <input
              className="category-name-input"
              data-initial-focus
              value={newCategoryName}
              ref={categoryNameInput}
              aria-invalid={duplicateName || undefined} aria-describedby={duplicateName ? 'category-name-error' : undefined}
              onChange={e => { setDuplicateName(false); setNewCategoryName(e.target.value); }}
              onKeyDown={event => { if (event.key === 'Enter' && !event.nativeEvent.isComposing && event.nativeEvent.keyCode !== 229) { event.preventDefault(); void handleCreateCategory(); } }}
              aria-label={t('message_category.name_placeholder')}
              placeholder={t('message_category.name_placeholder', 'Category name')}
              autoFocus
            />}

            {duplicateName && <p id="category-name-error" className="category-validation" role="alert">{t('review.action.duplicate')}</p>}
            <CategoryPalette expanded color={newCategoryColor} colorHex={newCategoryHex} onChange={(color, hex) => { setNewCategoryColor(color); setNewCategoryHex(hex); }} />
          </div>
        </Modal>
      )}

      {discardCategoryAction && <Modal title={t('message_edit.discard_title')} message="" confirmText={t('message_edit.discard')} cancelText={t('message_edit.keep')} destructive onCancel={() => setDiscardCategoryAction(null)} onConfirm={() => { discardCategoryAction(); setDiscardCategoryAction(null); }} />}

      {categoryManagerDeleteTarget && (
        <Modal
          title={t('review.action.delete_category', { name: categoryManagerDeleteTarget.name })}
          message={messages.some(message => !message.isDeleted && message.categoryId === categoryManagerDeleteTarget.id) ? t('message_category.delete_confirm_message') : ''}
          confirmText={t('common.delete', 'Delete')}
          cancelText={t('common.cancel', 'Cancel')}
          confirmDisabled={categorySaving} cancelDisabled={categorySaving} closeDisabled={categorySaving}
          onConfirm={() => { void (async () => {
            if (categoryWritePending.current || categoryManagerDeleteTarget.isDefault) return;
            ++fetchRevision.current; categoryWritePending.current = true; setCategorySaving(true);
            try {
              const id = categoryManagerDeleteTarget.id;
              if (id) await api.deleteMessageCategory(id);
              setCategoryManagerRows(rows => rows.filter(row => row.clientId !== categoryManagerDeleteTarget.clientId));
              setCategories(current => current.filter(category => category.id !== id));
              if (defaultCategory) {
                setMessages(current => current.map(message => message.categoryId === id ? { ...message, categoryId: defaultCategory.id, categoryName: defaultCategory.name, categoryColor: defaultCategory.color, categoryColorHex: defaultCategory.colorHex, categoryIsDefault: true } : message));
                setSelectedCategoryId(current => current === id ? defaultCategory.id : current);
                setDefaultSendCategoryId(current => current === id ? defaultCategory.id : current);
              }
              setCategoryManagerDeleteTarget(null); await fetchData(false);
            }
            catch { setCategoryManagerError({title:t('common.error'),message:t('navigation.save_failed')}); }
            finally { categoryWritePending.current = false; setCategorySaving(false); }
          })(); }}
          onCancel={() => setCategoryManagerDeleteTarget(null)}
          destructive
          size="compact"
        />
      )}

      {categoryManagerError && (
        <Modal
          title={categoryManagerError.title}
          message={categoryManagerError.message}
          hideCancel
          confirmText={t('common.ok', 'OK')}
          onConfirm={() => setCategoryManagerError(null)}
          onCancel={() => setCategoryManagerError(null)}
          size="compact"
        />
      )}
    </div>
  );
};
