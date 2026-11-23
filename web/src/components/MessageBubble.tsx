import { formatMessageTime } from '../utils/messageTime';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { api, MessageEditError, StorageError, type MessageCategory, type SyncaMessage } from '../api/client';
import { Check, Copy, Download, FileArchive, FileSpreadsheet, FileText, FileType2, Presentation, Pencil, Trash2 } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { Modal } from './Modal';
import { Toast } from './Toast';
import { CategoryAssignmentMenu } from './CategoryAssignmentMenu';
import { MessageMarkdown } from './MessageMarkdown';
import { ExpandableMessageText } from './ExpandableMessageText';
import { AuthImage } from './AuthImage';
import type { RecordMenuItem, RecordMenuOptions } from './SettingsPanel';
import { copyProtectedImage, copyText } from '../utils/clipboard';

interface Props {
  showsSeparator?: boolean;
  message: SyncaMessage;
  categories: MessageCategory[];
  onUpdate: () => void;
  onTextSaved: (message: SyncaMessage) => void;
  onEdit: (message: SyncaMessage) => void;
}

const CheckCircleFill = ({ size = 20, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="12" cy="12" r="10" fill={color} />
    <path d="M8 12L11 15L16 9" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const CheckCircleOutline = ({ size = 20, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="12" cy="12" r="10" stroke={color} strokeWidth="1.8" />
    <path d="M8 12L11 15L16 9" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const MessageBubble: React.FC<Props> = React.memo(({ message, categories, onUpdate, onEdit, onTextSaved, showsSeparator = true }) => {
  const [actionError, setActionError] = useState('');
  const canEditText = message.type === 'text' && !message.isDeleted && !message.imagePath && !message.imageUrl && !message.filePath && !message.fileUrl;
  const [copied, setCopied] = useState(false);
  const [isCopying, setIsCopying] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 2000);
    return () => window.clearTimeout(timer);
  }, [copied]);
  const [attachmentExpired, setAttachmentExpired] = useState(false);
  const expired = attachmentExpired || message.attachmentExpired || Boolean(message.attachmentExpiresAt && Date.parse(message.attachmentExpiresAt) <= Date.now());
  const [isProcessing, setIsProcessing] = useState(false);
  const [fileAction, setFileAction] = useState<'open' | 'download' | null>(null);
  const [isImageOpening, setIsImageOpening] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const { t, i18n } = useTranslation();
  const reportError = (error: unknown) => {
    if (error instanceof DOMException && error.name === 'AbortError') return;
    const expired = error instanceof StorageError && error.code === 'attachment_expired';
    if (expired) setAttachmentExpired(true);
    setActionError(t(expired ? 'storage.expired' : 'storage.action_failed'));
  };
  const openPreview = (objectUrl: string, previewWindow: Window | null) => {
    if (previewWindow) previewWindow.location.href = objectUrl;
    else window.open(objectUrl, '_blank', 'noopener,noreferrer');
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 60_000);
  };
  const fileExtension = useMemo(() => {
    if (!message.fileName) return '';
    const ext = message.fileName.split('.').pop();
    return ext ? ext.toUpperCase() : '';
  }, [message.fileName]);

  const fileIcon = useMemo(() => {
    const ext = fileExtension.toLowerCase();
    if (ext === 'pdf' || ext === 'txt' || ext === 'md') return <FileText size={22} />;
    if (ext === 'xls' || ext === 'xlsx' || ext === 'csv') return <FileSpreadsheet size={22} />;
    if (ext === 'ppt' || ext === 'pptx') return <Presentation size={22} />;
    if (ext === 'zip') return <FileArchive size={22} />;
    return <FileType2 size={22} />;
  }, [fileExtension]);

  const taskInFlight = useRef(false);
  const toggleTask = async (offset: number) => {
    const source = message.textContent;
    if (!canEditText || isProcessing || taskInFlight.current || !source) return;
    const marker = source[offset];
    if (source[offset - 1] !== '[' || source[offset + 1] !== ']' || ![' ', 'x', 'X'].includes(marker)) return;
    taskInFlight.current = true;
    setIsProcessing(true);
    setActionError('');
    try {
      const text = source.slice(0, offset) + (marker === ' ' ? 'x' : ' ') + source.slice(offset + 1);
      onTextSaved(await api.updateMessageText(message.id, text, message.updatedAt));
    } catch (error) {
      if (error instanceof MessageEditError) {
        setActionError(t(error.code === 'message_edit_conflict' ? 'message_task.conflict' : 'message_task.unavailable'));
        onUpdate();
      } else {
        setActionError(t('message_task.failed'));
      }
    } finally {
      taskInFlight.current = false;
      setIsProcessing(false);
    }
  };

  const handleClear = async () => {
    if (isProcessing) return;
    setIsProcessing(true);
    try {
      await api.setMessageCompletion(message.id, !message.isCleared);
      onUpdate();
    } catch (e) {
      reportError(e);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleCopy = async () => {
    if (isCopying || isProcessing || (message.type === 'image' && expired)) return;
    setIsCopying(true); setCopied(false); setActionError('');
    try {
      if (message.type === 'text') await copyText(message.textContent ?? '');
      else if (message.type === 'image' && message.imageUrl) await copyProtectedImage(message.imageUrl, message.attachmentExpiresAt);
      else return;
      setCopied(true);
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return;
      if (error instanceof StorageError && error.code === 'attachment_expired') reportError(error);
      else setActionError(t(message.type === 'image' ? 'message_bubble.copy_image_failed' : 'message_bubble.copy_failed'));
    } finally { setIsCopying(false); }
  };

  const handleDelete = async () => {
    setShowDeleteModal(false);
    setIsProcessing(true);
    try {
      await api.deleteMessage(message.id);
      onUpdate();
    } catch (e) {
      reportError(e);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleFileOpen = async () => {
    if (expired || !message.fileUrl || isProcessing) return;
    const previewWindow = window.open('', '_blank');
    if (previewWindow) {
      previewWindow.opener = null;
    }
    setIsProcessing(true);
    setFileAction('open');
    try {
      const objectUrl = await api.openProtectedFile(message.fileUrl, message.attachmentExpiresAt);
      openPreview(objectUrl, previewWindow);
    } catch (e) {
      previewWindow?.close();
      reportError(e);
    } finally {
      setFileAction(null);
      setIsProcessing(false);
    }
  };

  const handleFileDownload = async (event?: React.MouseEvent) => {
    event?.stopPropagation();
    if (expired || !message.fileUrl || isProcessing) return;
    setIsProcessing(true);
    setFileAction('download');
    try {
      await api.downloadProtectedFile(message.fileUrl, message.fileName, message.attachmentExpiresAt);
    } catch (e) {
      reportError(e);
    } finally {
      setFileAction(null);
      setIsProcessing(false);
    }
  };

  const handleImageOpen = async () => {
    if (expired || !message.imageUrl || isProcessing || isImageOpening) return;
    const previewWindow = window.open('', '_blank');
    if (previewWindow) {
      previewWindow.opener = null;
    }
    setIsImageOpening(true);
    try {
      const objectUrl = await api.openProtectedFile(message.imageUrl, message.attachmentExpiresAt);
      openPreview(objectUrl, previewWindow);
    } catch (e) {
      previewWindow?.close();
      reportError(e);
    } finally {
      setIsImageOpening(false);
    }
  };

  const handleImageKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      void handleImageOpen();
    }
  };

  const handleCategoryChange = async (categoryId: string) => {
    if (isProcessing || categoryId === message.categoryId) return;
    setIsProcessing(true);
    try {
      await api.updateMessageCategoryAssignment(message.id, categoryId);
      onUpdate();
    } catch (e) {
      reportError(e);
    } finally {
      setIsProcessing(false);
    }
  };

  const openRecordMenu = async (event: React.MouseEvent<HTMLDivElement> | React.KeyboardEvent<HTMLDivElement>) => {
    const recordMenu = window.syncaDesktop?.recordMenu;
    const target = event.target;
    const row = event.currentTarget;
    if (!recordMenu || !(target instanceof Element) || !row.contains(target) ||
      target.closest('input:not([type=checkbox]), textarea, [contenteditable=true]')) return;
    event.preventDefault();
    event.stopPropagation();
    const selection = window.getSelection();
    const hasSelection = Boolean(selection && !selection.isCollapsed && selection.rangeCount && selection.getRangeAt(0).intersectsNode(row));
    const link = target.closest<HTMLAnchorElement>('a[href]')?.href;
    const items: (RecordMenuItem | null)[] = [];
    if (hasSelection) items.push({id: 'copySelection', label: t('desktop_menu.copy_selection')});
    if (link) items.push({id: 'openLink', label: t('desktop_menu.open_link')}, {id: 'copyLink', label: t('desktop_menu.copy_link')});
    if (items.length) items.push(null);
    const url = message.type === 'image' ? message.imageUrl : message.fileUrl;
    const attachment = !expired && url && message.type !== 'text' ? {
      url, name: message.fileName || url.split('/').pop() || 'attachment', kind: message.type, expiresAt: message.attachmentExpiresAt,
    } : undefined;
    const enabled = !isProcessing;
    if (canEditText) items.push({id: 'edit', label: t('message_edit.title'), enabled});
    if (message.type === 'text' || attachment?.kind === 'image') items.push({id: 'copyRecord',
      label: t(message.type === 'text' && hasSelection ? 'desktop_menu.copy_record' : 'common.copy'), enabled: enabled && !isCopying});
    if (attachment) {
      if (attachment.kind === 'image' && window.syncaDesktop?.platform === 'macOS') items.push({id: 'preview', label: t('message_bubble.open_with_preview'), enabled});
      items.push({id: 'save', label: t('common.save'), enabled},
        {id: 'saveAs', label: t('message_bubble.save_as'), enabled},
        {id: 'reveal', label: t(window.syncaDesktop?.platform === 'macOS' ? 'message_bubble.show_in_finder' : 'desktop_menu.show_folder'), enabled});
    }
    if (items.length && items.at(-1) !== null) items.push(null);
    items.push({id: 'complete', label: t(message.isCleared ? 'storage.mark_incomplete' : 'storage.mark_complete'), enabled});
    if (categories.length) items.push({id: 'category', label: t('storage.message_category'), enabled, options: categories.map(category => ({
      id: category.id, label: category.isDefault ? t('message_category.default_badge') : category.name, checked: category.id === message.categoryId,
    }))});
    items.push(null, {id: 'delete', label: t('common.delete'), enabled});
    const bounds = target.getBoundingClientRect();
    const options: RecordMenuOptions = {items, attachment, link,
      text: message.type === 'text' ? message.textContent ?? '' : undefined,
      selection: hasSelection ? selection?.toString() : undefined,
      x: 'clientX' in event ? event.clientX : bounds.left + 8, y: 'clientY' in event ? event.clientY : bounds.top + 8};
    try {
      const action = await recordMenu(options);
      if (!action || !row.isConnected) return;
      if (action === 'edit') onEdit(message);
      else if (action === 'copied') setCopied(true);
      else if (action === 'complete') await handleClear();
      else if (action === 'delete') setShowDeleteModal(true);
      else if (action === 'save' && attachment) {
        if (attachment.kind === 'file') await handleFileDownload();
        else await api.downloadProtectedFile(attachment.url, attachment.name, attachment.expiresAt);
      } else if (action.startsWith('category:')) {
        const id = action.slice('category:'.length);
        if (categories.some(category => category.id === id)) await handleCategoryChange(id);
      }
    } catch (error) { if (row.isConnected) reportError(error); }
  };

  const formatFileSize = (bytes: number | null) => {
    if (!bytes || bytes <= 0) return '';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <>
      <div data-message-id={message.id} tabIndex={-1}
        onContextMenu={openRecordMenu}
        onKeyDown={event => { if (event.key === 'ContextMenu' || (event.shiftKey && event.key === 'F10')) void openRecordMenu(event); }}
        className={`message-bubble ${message.isCleared ? 'cleared' : ''} ${showsSeparator ? '' : 'message-bubble-last'}`}>
        {message.type !== 'text' && expired && <p className="attachment-expiry">{t('storage.expired')}</p>}
        {message.type !== 'text' && !expired && message.attachmentExpiresAt && <p className="attachment-expiry">{t('storage.expires')}: {new Date(message.attachmentExpiresAt).toLocaleString()}</p>}
        {message.type === 'text' && (
          <ExpandableMessageText text={message.textContent ?? ''}>
            <MessageMarkdown text={message.textContent ?? ''} taskLabel={t('message_task.label')}
              taskPending={isProcessing} onTaskToggle={canEditText ? toggleTask : undefined} />
          </ExpandableMessageText>
        )}
        
        {!expired && message.type === 'image' && message.imageUrl && (
          <AuthImage
            url={message.imageUrl}
            expiresAt={message.attachmentExpiresAt}
            alt={t('storage.shared_image')}
            className={`message-image ${isImageOpening ? 'opening' : ''}`}
            onClick={() => void handleImageOpen()}
            onKeyDown={handleImageKeyDown}
            role="button"
            tabIndex={0}
            aria-label={t('image_preview.open', 'Open image')}
          />
        )}

        {!expired && message.type === 'file' && (
          <button className="file-card" onClick={handleFileOpen} disabled={isProcessing}>
            <div className="file-card-icon">{fileIcon}</div>
            <div className="file-card-meta">
              <div className="file-card-name">{message.fileName ?? t('storage.shared_file')}</div>
              <div className="file-card-detail">
                {fileExtension && <span>{fileExtension}</span>}
                {message.fileSize != null && <span>{formatFileSize(message.fileSize)}</span>}
                {fileAction === 'open' && <span>{t('common.opening', 'Opening...')}</span>}
              </div>
            </div>
          </button>
        )}

        <div className="message-header">
          <div className="message-metadata">
            <span>{formatMessageTime(message.createdAt, i18n.language, t('message.date.yesterday'))}</span>
            {message.categoryName && (
              <>
                <span>·</span>
                <CategoryAssignmentMenu categories={categories} categoryId={message.categoryId} disabled={isProcessing} onChange={handleCategoryChange} />
              </>
            )}
          </div>
          
          <div className="actions">
            {canEditText && <button className="action-btn" onClick={() => onEdit(message)} disabled={isProcessing}
              title={t('message_edit.title')} aria-label={t('message_edit.title')}><Pencil size={16} aria-hidden="true" /></button>}
            {!expired && message.type === 'file' && (
              <button className="action-btn" onClick={handleFileDownload} disabled={isProcessing} title={t('common.save', 'Save')}>
                {fileAction === 'download' ? <span className="action-spinner" aria-hidden="true" /> : <Download size={16} />}
              </button>
            )}
            {(message.type === 'text' || (message.type === 'image' && !expired && message.imageUrl)) && (
              <button className={`action-btn message-copy${copied ? ' is-copied' : ''}`} onClick={() => void handleCopy()} disabled={isProcessing || isCopying}
                title={t(copied ? 'message_bubble.copied' : 'common.copy')} aria-label={t(copied ? 'message_bubble.copied' : 'common.copy')} aria-busy={isCopying}>
                {isCopying ? <span className="action-spinner" aria-hidden="true" /> : copied ? <Check size={16} aria-hidden="true" /> : <Copy size={16} aria-hidden="true" />}
              </button>
            )}
            <button className="action-btn" onClick={() => setShowDeleteModal(true)} disabled={isProcessing} title={t('common.delete', 'Delete')}>
              <Trash2 size={16} />
            </button>
            <button 
              className={`action-btn ${message.isCleared ? 'cleared-icon' : ''}`} 
              aria-label={t(message.isCleared ? 'storage.mark_incomplete' : 'storage.mark_complete')}
              onClick={handleClear} 
              disabled={isProcessing}
            >
              {message.isCleared ? (
                <CheckCircleFill size={18} color="var(--cleared-icon-color)" />
              ) : (
                <CheckCircleOutline size={18} color="var(--text-secondary)" />
              )}
            </button>
          </div>
        </div>
      </div>

      <span className="copy-announcement" role="status">{copied ? t('message_bubble.copied') : ''}</span>
      <Toast variant="error" duration={6000} message={actionError} visible={Boolean(actionError)} onClose={() => setActionError('')} />
      {showDeleteModal && (
        <Modal
          title={t('message_bubble.delete_confirm_title', 'Confirm Delete')}
          message={t('message_bubble.delete_confirm_message', 'This will permanently delete this record from the cloud and cannot be undone.').replace('%@', '')}
          confirmText={t('common.delete', 'Delete')}
          cancelText={t('common.cancel', 'Cancel')}
          onConfirm={handleDelete}
          onCancel={() => setShowDeleteModal(false)}
          destructive
        />
      )}
    </>
  );
});
