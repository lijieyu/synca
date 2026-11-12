import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { useTranslation } from 'react-i18next';
import './AppLoading.css';

const LOADING_DELAY_MS = 250;

/** Keep fast route loads quiet; announce genuinely slow loads without layout jumps. */
export function AppLoading({ overlay = false }: { overlay?: boolean }) {
  const { t } = useTranslation();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const timer = window.setTimeout(() => setVisible(true), LOADING_DELAY_MS);
    return () => window.clearTimeout(timer);
  }, []);

  const indicator = (
    <div className={`app-loading${overlay ? ' app-loading-overlay' : ''}`} role="status" aria-label={visible ? t('message_list.loading') : undefined}>
      {visible && <div className="app-loading-indicator">
        <span className="app-loading-spinner" aria-hidden="true" />
      </div>}
    </div>
  );
  return overlay ? createPortal(indicator, document.body) : indicator;
}
