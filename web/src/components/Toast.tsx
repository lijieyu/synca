import React, { useEffect } from 'react';

interface Props {
  message: string;
  visible: boolean;
  onClose: () => void;
  duration?: number;
}

export const Toast: React.FC<Props> = ({ message, visible, onClose, duration = 2000 }) => {
  useEffect(() => {
    if (visible) {
      const timer = setTimeout(onClose, duration);
      return () => clearTimeout(timer);
    }
  }, [visible, onClose, duration]);

  if (!visible) return null;

  return (
    <div style={{
      position: 'fixed',
      top: '64px',
      left: '50%',
      transform: 'translateX(-50%)',
      background: 'rgba(48, 209, 88, 0.9)',
      color: '#fff',
      padding: '8px 20px',
      borderRadius: '20px',
      fontSize: '14px',
      fontWeight: 500,
      zIndex: 1000,
      backdropFilter: 'blur(10px)',
      WebkitBackdropFilter: 'blur(10px)',
      boxShadow: '0 2px 12px rgba(48, 209, 88, 0.3)',
      animation: 'toastIn 0.3s ease',
    }}>
      {message}
    </div>
  );
};
