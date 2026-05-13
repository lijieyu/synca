import React from 'react';

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
}

export const Modal: React.FC<Props> = ({ 
  title, message, confirmText = 'OK', cancelText = 'Cancel',
  onConfirm, onCancel, leadingActionText, onLeadingAction, destructive = false, children, size
}) => {
  const contentSizeClass = size === 'compact' ? '' : (children || size === 'large' ? 'modal-content-large' : '');

  return (
    <div className="modal-overlay" onClick={onCancel}>
      <div className={`modal-content ${contentSizeClass}`} onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="modal-title">
        <h3 id="modal-title" className="modal-title">{title}</h3>
        {message ? <p className="modal-message">{message}</p> : null}
        {children}
        <div className={`modal-actions ${leadingActionText && onLeadingAction ? 'modal-actions-with-leading' : ''}`}>
          {leadingActionText && onLeadingAction && (
            <button className="modal-leading-action" onClick={onLeadingAction}>{leadingActionText}</button>
          )}
          <div className="modal-primary-actions">
            <button className="modal-btn modal-btn-cancel" onClick={onCancel}>{cancelText}</button>
            <button 
              className={`modal-btn ${destructive ? 'modal-btn-destructive' : 'modal-btn-confirm'}`} 
              onClick={onConfirm}
            >
              {confirmText}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
