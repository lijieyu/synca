import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import './AppLoading.css';

const LOADING_DELAY_MS = 250;

/** Keep fast route loads quiet; announce genuinely slow loads without layout jumps. */
export function AppLoading() {
  const { t } = useTranslation();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const timer = window.setTimeout(() => setVisible(true), LOADING_DELAY_MS);
    return () => window.clearTimeout(timer);
  }, []);

  return (
    <div className="app-loading" role="status" aria-live="polite">
      {visible && <div className="app-loading-indicator">
        <span className="app-loading-spinner" aria-hidden="true" />
        <span>{t('message_list.loading')}</span>
      </div>}
    </div>
  );
}
