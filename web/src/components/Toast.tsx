import React, { useEffect, useLayoutEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import './Toast.css';

interface Props {
  message: string;
  visible: boolean;
  onClose: () => void;
  duration?: number;
  variant?: 'success' | 'error';
}

export const Toast: React.FC<Props> = ({ message, visible, onClose, duration = 2000, variant = 'success' }) => {
  const notice = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (visible) {
      const timer = setTimeout(onClose, duration);
      return () => clearTimeout(timer);
    }
  }, [visible, message, onClose, duration]);

  useLayoutEffect(() => {
    if (!visible || !notice.current) return;
    const node = notice.current;
    let anchor: Element | null = null;
    const resize = new ResizeObserver(place);
    function place() {
      // Escape list/editor transforms and use the active surface, including settings.
      const headers = document.querySelectorAll('.modal-content .modal-header');
      const header = headers[headers.length - 1] ?? document.querySelector('.settings-veil .settings-title') ?? document.querySelector('.calm-main > .header');
      if (header !== anchor) {
        if (anchor) resize.unobserve(anchor);
        if (header) resize.observe(header);
        anchor = header;
      }
      const bounds = header?.getBoundingClientRect();
      const left = bounds ? bounds.x + bounds.width / 2 : window.innerWidth / 2;
      node.style.maxWidth = `${Math.max(0, Math.min(560, (bounds?.width ?? window.innerWidth) - 32))}px`;
      const pill = node.getBoundingClientRect();
      let top = bounds ? bounds.y + bounds.height / 2 : 48;
      // Long errors cannot share the compact header with its title and controls.
      const overlaps = bounds && [...(header?.querySelectorAll('.header-actions, .mobile-category-trigger, .settings-close, .modal-close') ?? [])].some(element => {
        const control = element.getBoundingClientRect();
        return left + pill.width / 2 + 8 > control.left && left - pill.width / 2 - 8 < control.right;
      });
      if (bounds && (pill.height > bounds.height - 16 || overlaps)) top = bounds.bottom + 12 + pill.height / 2;
      node.style.left = `${left}px`;
      node.style.top = `${top}px`;
    }
    resize.observe(node);
    place();
    const mutation = new MutationObserver(place);
    mutation.observe(document.body, { childList: true, subtree: true });
    window.addEventListener('resize', place);
    window.addEventListener('scroll', place, true);
    return () => { resize.disconnect(); mutation.disconnect(); window.removeEventListener('resize', place); window.removeEventListener('scroll', place, true); };
  }, [visible, message]);

  if (!visible) return null;
  return createPortal(<div ref={notice} className="app-toast" data-variant={variant}
    role={variant === 'error' ? 'alert' : 'status'} aria-atomic="true">{message}</div>, document.body);
};
