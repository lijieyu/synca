import React, { useEffect } from 'react';

interface Props {
  message: string;
  visible: boolean;
  onClose: () => void;
  duration?: number;
  variant?: 'success' | 'error';
}

export const Toast: React.FC<Props> = ({ message, visible, onClose, duration = 2000, variant = 'success' }) => {
  useEffect(() => {
    if (visible) {
      const timer = setTimeout(onClose, duration);
      return () => clearTimeout(timer);
    }
  }, [visible, onClose, duration]);

  if (!visible) return null;

  return (
    <div role={variant === 'error' ? 'alert' : 'status'} style={{
      position: 'fixed',
      top: '64px',
      left: '50%',
      transform: 'translateX(-50%)',
      background: variant === 'error' ? '#b42318' : '#18752c',
      color: '#fff',
      padding: '8px 20px',
      borderRadius: '20px',
      fontSize: '14px',
      fontWeight: 500,
      zIndex: 1000,
      backdropFilter: 'blur(10px)',
      WebkitBackdropFilter: 'blur(10px)',
      boxShadow: '0 2px 12px rgba(0, 0, 0, 0.2)',
      maxWidth: 'calc(100vw - 32px)',
      width: 'max-content',
      boxSizing: 'border-box',
      overflowWrap: 'anywhere',
      animation: 'toastIn 0.3s ease',
    }}>
      {message}
    </div>
  );
};
