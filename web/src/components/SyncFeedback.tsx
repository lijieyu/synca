import { useLayoutEffect, useState } from 'react';
import './SyncFeedback.css';

/** Keep the existing success toast appearance, centered inside the record header. */
export function SyncFeedback({ sequence, label }: { sequence: number; label: string }) {
  const [visible, setVisible] = useState(false);
  useLayoutEffect(() => {
    if (!sequence) return;
    setVisible(true);
    const timeout = window.setTimeout(() => setVisible(false), 2200);
    return () => window.clearTimeout(timeout);
  }, [sequence]);
  return <div className="sync-feedback" data-visible={visible} role="status" aria-live="polite" aria-atomic="true">
    {visible ? label : ''}
  </div>;
}
