import React, { useEffect, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { api, StorageError } from '../api/client';

interface AuthImageProps extends React.ImgHTMLAttributes<HTMLImageElement> {
  url: string;
  expiresAt?: string | null;
}

export const AuthImage: React.FC<AuthImageProps> = ({ url, expiresAt, ...props }) => {
  const container = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [error, setError] = useState<'load' | 'expired' | null>(null);
  const [retry, setRetry] = useState(0);
  const { t } = useTranslation();

  useEffect(() => {
    if (!('IntersectionObserver' in window)) return;
    const observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) {
        setVisible(true);
        observer.disconnect();
      }
    }, { rootMargin: '200px' });
    if (container.current) observer.observe(container.current);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!visible && 'IntersectionObserver' in window) return;
    const controller = new AbortController();
    let currentObjectUrl: string | null = null;
    setObjectUrl(null);
    setError(null);
    void api.getProtectedFileBlob(url, { signal: controller.signal, expiresAt, cacheImage: true }).then(blob => {
      if (controller.signal.aborted) return;
      currentObjectUrl = URL.createObjectURL(blob);
      setObjectUrl(currentObjectUrl);
    }).catch(err => {
      if (!controller.signal.aborted) setError(err instanceof StorageError && err.code === 'attachment_expired' ? 'expired' : 'load');
    });
    return () => {
      controller.abort();
      if (currentObjectUrl) URL.revokeObjectURL(currentObjectUrl);
    };
  }, [url, expiresAt, visible, retry]);

  return <div ref={container} className="auth-image">
    {objectUrl ? <img src={objectUrl} decoding="async" {...props} /> : error === 'load' ?
      <button className="attachment-placeholder" onClick={() => setRetry(value => value + 1)}>{t('message_bubble.load_failed_retry')}</button> :
      <div className="attachment-placeholder" role="status">{t(error === 'expired' ? 'storage.expired' : 'message_list.loading', 'Loading...')}</div>}
  </div>;
};
