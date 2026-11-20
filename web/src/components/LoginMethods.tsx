import { useEffect, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { api, type LoginMethods as Methods } from '../api/client';
import { useAuth } from '../contexts/AuthContext';
import { authorizeApple, loadApple } from '../auth/apple';
import { EmailVerification, authErrorKey } from './EmailVerification';
import './LoginView.css';
export function LoginMethods() {
  const { token } = useAuth();
  return <LoginMethodsSession key={token} />;
}
function LoginMethodsSession() {
  const { refreshAccessStatus } = useAuth();
  const { t } = useTranslation(); const [methods, setMethods] = useState<Methods | null>(null);
  const [email, setEmail] = useState(false); const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [notice, setNotice] = useState(''); const [reload, setReload] = useState(0);
  const [appleChallenge, setAppleChallenge] = useState<{challengeId: string; nonce: string; expiresAt?: string} | null>(null);
  const request = useRef<AbortController | null>(null); const session = useRef(localStorage.getItem('authToken'));
  useEffect(() => {
    const controller = new AbortController();
    let expiry: ReturnType<typeof setTimeout> | undefined;
    setAppleChallenge(null);
    void api.getLoginMethods(controller.signal).then(async result => {
      if (controller.signal.aborted) return;
      setMethods(result); setError('');
      if (!result.apple) {
        await loadApple();
        const challenge = await api.appleBindingChallenge(controller.signal);
        if (!controller.signal.aborted) { setAppleChallenge(challenge); const refresh = () => { if (request.current) expiry = setTimeout(refresh, 30_000); else setReload(value => value + 1); }; const expiresAt = challenge.expiresAt ? Date.parse(challenge.expiresAt) : NaN; const delay = Number.isFinite(expiresAt) ? Math.max(1000, expiresAt - Date.now() - 60_000) : 8 * 60 * 1000; expiry = setTimeout(refresh, delay); }
      }
    }).catch(err => { if (!controller.signal.aborted) setError(t(authErrorKey(err))); });
    void loadApple().catch(() => {});
    return () => { clearTimeout(expiry); controller.abort(); request.current?.abort(); };
  }, [reload, t]);
  async function bindApple() {
    if (request.current || !appleChallenge) return;
    const controller = new AbortController(); request.current = controller; setBusy(true); setError(''); setNotice('');
    try {
      const challenge = appleChallenge;
      const apple = await authorizeApple(controller.signal, challenge.nonce);
      if (controller.signal.aborted || session.current !== localStorage.getItem('authToken')) return;
      const result = await api.bindApple(challenge.challengeId, apple.idToken, controller.signal);
      if (!controller.signal.aborted && session.current === localStorage.getItem('authToken')) { setMethods(result); setNotice(t('email_auth.bound')); }
    } catch (err) { if (!controller.signal.aborted) { setError(t(authErrorKey(err))); setAppleChallenge(null); } }
    finally { if (!controller.signal.aborted) setBusy(false); if (request.current === controller) request.current = null; }
  }
  return <section className="login-methods" aria-label={t('email_auth.methods')}>
    {email ? <EmailVerification binding onBack={() => setEmail(false)} onBound={result => { setMethods(result); setEmail(false); setNotice(t('email_auth.bound')); void refreshAccessStatus(); }} /> : <><h3>{t('email_auth.methods')}</h3><p className="auth-hint">{t('email_auth.methods_hint')}</p>
      {methods ? <div className="login-method-rows"><div><span><strong>Apple</strong><small>{t(methods.apple ? 'email_auth.linked' : 'email_auth.unlinked')}</small></span>{!methods.apple && <button disabled={busy || !appleChallenge} onClick={() => void bindApple()}>{t(busy ? 'email_auth.apple_wait' : 'email_auth.bind')}</button>}</div><div><span><strong>{t('email_auth.email_label')}</strong><small dir="auto">{methods.email || t('email_auth.unlinked')}</small></span>{!methods.email && <button disabled={busy} onClick={() => { setError(''); setNotice(''); setEmail(true); }}>{t('email_auth.bind')}</button>}</div></div> : !error && <p role="status">{t('email_auth.loading')}</p>}
      {busy && <button className="auth-back" onClick={() => { request.current?.abort(); request.current = null; setBusy(false); setReload(value => value + 1); }}>{t('common.cancel')}</button>}
      {error && <p className="auth-notice" role="alert">{error}{(!methods || (!methods.apple && !appleChallenge)) && <button className="auth-back" onClick={() => setReload(reload + 1)}>{t('email_auth.retry')}</button>}</p>}{notice && <p className="auth-hint" role="status">{notice}</p>}
    </>}
  </section>;
}
