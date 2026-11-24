import { useEffect, useState } from 'react';
import { api } from '../api/client';

export function useEmailAvailability() {
  // Existing protected preview releases predate capability discovery.
  const preview = !!(window.syncaDesktop as {preview?: boolean} | undefined)?.preview || window.location.hostname === 'synca-preview.haerth.cn';
  // Desktop login methods are product capabilities, not network loading states.
  const desktop = window.syncaDesktop?.emailAuth === true;
  const [available, setAvailable] = useState(preview);
  useEffect(() => {
    if (desktop) return;
    const controller = new AbortController();
    void api.emailAvailable(controller.signal, preview).then(value => {
      if (!controller.signal.aborted) setAvailable(value);
    });
    return () => controller.abort();
  }, [preview, desktop]);
  return desktop || available;
}
