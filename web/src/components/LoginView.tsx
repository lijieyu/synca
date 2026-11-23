import { useEmailAvailability } from '../auth/useEmailAvailability';
import appleLogoWhite from '../assets/apple-sign-in/logo-white.svg?no-inline';
import appleLogoBlack from '../assets/apple-sign-in/logo-black.svg?no-inline';
import { Mail } from 'lucide-react';
import { AuthTerms } from './AuthTerms';
import { useEffect, useRef, useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { api, type AuthResponse } from '../api/client';
import { useTranslation } from 'react-i18next';
import { authorizeApple, loadApple } from '../auth/apple';
import { EmailVerification, authErrorKey } from './EmailVerification';
import './LoginView.css';

export function LoginView() {
  const desktop = (window as Window & { syncaDesktop?: { preview?: boolean; localPreview?: boolean } }).syncaDesktop;
  const preview = !!desktop?.preview; const localPreview = !!desktop?.localPreview;
  const emailAvailable = useEmailAvailability();
  const { login } = useAuth(); const { t } = useTranslation();
  const [email, setEmail] = useState(false); const [emailDraft, setEmailDraft] = useState(localPreview ? 'synca-beta@example.invalid' : ''); const [busy, setBusy] = useState(false); const [error, setError] = useState('');
  const request = useRef<AbortController | null>(null);
  const session = useRef(localStorage.getItem('authToken'));
  useEffect(() => { if (!preview) void loadApple().catch(() => {}); return () => request.current?.abort(); }, [preview]);
  const authenticated = (res: AuthResponse) => login(res.token, res.user.isAdmin, res.user.email);
  async function appleLogin() {
    if (request.current) return;
    const controller = new AbortController(); request.current = controller; setBusy(true); setError('');
    try {
      const apple = await authorizeApple(controller.signal);
      if (controller.signal.aborted || session.current !== localStorage.getItem('authToken')) return;
      const response = await api.loginWithApple(apple.idToken, apple.name);
      if (!controller.signal.aborted && session.current === localStorage.getItem('authToken')) authenticated(response);
    } catch (err) { if (!controller.signal.aborted) setError(t(authErrorKey(err))); }
    finally { if (!controller.signal.aborted) setBusy(false); if (request.current === controller) request.current = null; }
  }
  return <main className={`desktop-auth ${email ? 'desktop-auth-form' : ''}`}>
    <div className="desktop-auth-content">{email ? <EmailVerification initialEmail={emailDraft} onEmailChange={setEmailDraft} onBack={() => setEmail(false)} onAuthenticated={authenticated} localPreview={localPreview} /> : <>
      <div className="auth-brand"><img src="/logo.png?v=a2" alt="" width={72} height={72} /><h1>Synca</h1><p>{t('app.slogan')}</p></div>
      {preview && <p className="auth-notice">{t(localPreview ? 'email_auth.local_preview_notice' : 'email_auth.preview_notice')}</p>}
      <div className="auth-actions">{!preview && <button className="auth-primary auth-apple auth-apple-signin" disabled={busy} onClick={() => void appleLogin()}><img className="auth-apple-logo auth-apple-logo-white" src={appleLogoWhite} alt="" aria-hidden="true" /><img className="auth-apple-logo auth-apple-logo-black" src={appleLogoBlack} alt="" aria-hidden="true" />{t(busy ? 'email_auth.apple_wait' : 'email_auth.apple_login')}</button>}{emailAvailable && <button className="auth-secondary auth-apple" disabled={busy} onClick={() => { setError(''); setEmail(true); }}><Mail size={18} aria-hidden="true" />{t('email_auth.email_login')}</button>}</div>
      {busy && <button className="auth-back" onClick={() => { request.current?.abort(); request.current = null; setBusy(false); }}>{t('common.cancel')}</button>}
      {error && <p className="auth-notice" role="alert">{error}</p>}
      <AuthTerms />
    </>}</div>
  </main>;
}
