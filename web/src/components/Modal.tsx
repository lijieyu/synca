import React from 'react';
import { createPortal } from 'react-dom';

interface Props {
  title: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  onConfirm: () => void;
  onCancel: () => void;
  leadingActionText?: string;
  onLeadingAction?: () => void;
  destructive?: boolean;
  children?: React.ReactNode;
  size?: 'compact' | 'large';
  hideCancel?: boolean;
  className?: string;
  secondaryAction?: React.ReactNode;
  neutral?: boolean;
}

export const Modal: React.FC<Props> = ({
  title, message, confirmText = 'OK', cancelText = 'Cancel',
  onConfirm, onCancel, leadingActionText, onLeadingAction, destructive = false, children, size, hideCancel = false, className = '', secondaryAction, neutral = false
}) => {
  const titleID = React.useId();
  const dialogRef = React.useRef<HTMLDivElement>(null);
  const cancelRef = React.useRef(onCancel);
  React.useLayoutEffect(() => { cancelRef.current = onCancel; }, [onCancel]);
  const contentSizeClass = size === 'compact' ? '' : (children || size === 'large' ? 'modal-content-large' : '');

  React.useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    dialogRef.current?.focus();
    const handleKeyDown = (event: KeyboardEvent) => {
      if ([...document.querySelectorAll('[role=dialog]')].at(-1) !== dialogRef.current) return;
      if (event.key === 'Tab') {
        const items = [...(dialogRef.current?.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), a[href]') ?? [])].filter(item => item.getClientRects().length > 0);
        const first = items[0], last = items[items.length - 1];
        if (event.shiftKey && (document.activeElement === first || document.activeElement === dialogRef.current)) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
      }
      if (event.key === 'Escape') {
        event.preventDefault();
        cancelRef.current();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => { window.removeEventListener('keydown', handleKeyDown); previous?.focus(); };
  }, []);

  return createPortal(
    <div className="modal-overlay" onClick={onCancel}>
      <div ref={dialogRef} tabIndex={-1} className={`modal-content ${contentSizeClass} ${className}`} onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby={titleID}>
        <h3 id={titleID} className="modal-title">{title}</h3>
        {message ? <p className="modal-message">{message}</p> : null}
        {children}
        <div className={`modal-actions ${leadingActionText && onLeadingAction ? 'modal-actions-with-leading' : ''}`}>
          {leadingActionText && onLeadingAction && (
            <button className="modal-leading-action" onClick={onLeadingAction}>{leadingActionText}</button>
          )}
          <div className="modal-primary-actions">
            {secondaryAction}
            {!hideCancel && <button className="modal-btn modal-btn-cancel" onClick={onCancel}>{cancelText}</button>}
            <button
              className={`modal-btn ${destructive ? 'modal-btn-destructive' : neutral ? 'modal-btn-cancel' : 'modal-btn-confirm'}`}
              onClick={onConfirm}
            >
              {confirmText}
            </button>
          </div>
        </div>
      </div>
    </div>, document.body
  );
};
