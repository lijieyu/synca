import { useLayoutEffect, useRef, type ReactNode } from 'react';
import { useTranslation } from 'react-i18next';

export function MobileCategoryDrawer({ open, onClose, children }: {
  open: boolean; onClose: () => void; children: ReactNode;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const start = useRef<{x:number; y:number} | null>(null);
  const { t } = useTranslation();
  useLayoutEffect(() => {
    if (open) dialog.current?.showModal();
    else dialog.current?.close();
  }, [open]);
  return <dialog className="mobile-categories" ref={dialog} aria-label={t('message_category.section_title')}
    onCancel={onClose} onClick={event => { if (event.target === event.currentTarget) onClose(); }}
    onTouchStart={event => {
      const touch = event.touches[0];
      start.current = event.touches.length === 1 ? {x:touch.clientX,y:touch.clientY} : null;
    }}
    onTouchCancel={()=>{start.current=null}}
    onTouchEnd={event=>{
      const touch=event.changedTouches[0], origin=start.current; start.current=null;
      if(origin && origin.x-touch.clientX>60 && origin.x-touch.clientX>2*Math.abs(origin.y-touch.clientY)) onClose();
    }}>{children}</dialog>;
}
