import { AuthTerms } from './AuthTerms';
import { useEffect, useId, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { api, AuthError, type AuthResponse, type EmailChallenge, type LoginMethods } from '../api/client';

export function authErrorKey(error: unknown) {
  const code = error instanceof AuthError ? error.code : error instanceof Error ? error.message : '';
  return `email_auth.errors.${['invalid_email','invalid_code','code_expired','code_attempts_exceeded','rate_limited','email_unavailable','email_send_failed','email_in_use','apple_in_use','email_already_bound','apple_already_bound','apple_cancelled','apple_timeout','apple_unavailable','apple_auth_failed'].includes(code) ? code : 'generic'}`;
}
export function EmailVerification({ binding = false, initialEmail = '', onEmailChange, onBack, onAuthenticated, onBound }: {
  binding?: boolean; initialEmail?: string; onEmailChange?: (email: string) => void; onBack: () => void; onAuthenticated?: (response: AuthResponse) => void; onBound?: (methods: LoginMethods) => void;
}) {
  const { t, i18n } = useTranslation();
  const id = useId();
  const [email, setEmail] = useState(initialEmail); const [code, setCode] = useState('');
  const [challenge, setChallenge] = useState<EmailChallenge | null>(null);
  const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [notice, setNotice] = useState('');
  const [now, setNow] = useState(Date.now()); const [retryAt, setRetryAt] = useState(0);
  const input = useRef<HTMLInputElement>(null); const request = useRef<AbortController | null>(null);
  const session = useRef(localStorage.getItem('authToken'));
  useEffect(() => { const timer = setInterval(() => setNow(Date.now()), 1000); return () => { clearInterval(timer); request.current?.abort(); }; }, []);
  useEffect(() => { input.current?.focus(); }, [challenge?.challengeId]);
  const seconds = Math.max(0, Math.ceil((Math.max(retryAt, challenge ? Date.parse(challenge.resendAt) : 0) - now) / 1000));
  const current = (controller: AbortController) => !controller.signal.aborted && session.current === localStorage.getItem('authToken');
  const fail = (err: unknown, controller: AbortController) => {
    if (!current(controller)) return;
    setError(t(authErrorKey(err)));
    if (err instanceof AuthError && err.retryAfter) setRetryAt(Date.now() + err.retryAfter * 1000);
    input.current?.focus();
  };
  async function send() {
    if (request.current || seconds > 0) return;
    if (!challenge && (!input.current?.validity.valid || !email.trim())) { setError(t('email_auth.errors.invalid_email')); input.current?.focus(); return; }
    const controller = new AbortController(); request.current = controller; setBusy(true); setError(''); setNotice('');
    try {
      const next = await api.sendEmailCode(email.trim(), i18n.language, binding, controller.signal);
      if (!current(controller)) return;
      if (challenge) setNotice(t('email_auth.resent'));
      setEmail(email.trim()); setChallenge(next); setCode(''); setNow(Date.now());
    } catch (err) { fail(err, controller); }
    finally { if (current(controller)) setBusy(false); if (request.current === controller) request.current = null; }
  }
  async function verify() {
    if (request.current || !challenge) return;
    if (!/^\d{6}$/.test(code)) { setError(t('email_auth.errors.invalid_code')); input.current?.focus(); return; }
    const controller = new AbortController(); request.current = controller; setBusy(true); setError('');
    try {
      if (binding) { const result = await api.bindEmail(challenge.challengeId, code, controller.signal); if (current(controller)) onBound?.(result); }
      else { const result = await api.verifyEmailCode(challenge.challengeId, code, controller.signal); if (current(controller)) onAuthenticated?.(result); }
    } catch (err) { fail(err, controller); }
    finally { if (current(controller)) setBusy(false); if (request.current === controller) request.current = null; }
  }
  const back = () => { request.current?.abort(); request.current = null; setBusy(false); setError(''); setNotice(''); if (challenge) { setChallenge(null); setCode(''); } else onBack(); };
  return <section className="email-verification" data-step={challenge ? 'code' : 'email'}>
    <button type="button" className="auth-back" onClick={back}>← {t(challenge ? 'email_auth.change_email' : 'email_auth.back')}</button>
    <h1>{t(challenge ? 'email_auth.check_code' : binding ? 'email_auth.add_email' : 'email_auth.email_login')}</h1>
    <p className="auth-description">{challenge ? t('email_auth.sent_to') : t(binding ? 'email_auth.bind_description' : 'email_auth.description')}</p>
    {challenge && <p className="auth-address" dir="auto">{email}</p>}
    <form noValidate onSubmit={event => { event.preventDefault(); void (challenge ? verify() : send()); }}>
      <label htmlFor={`${id}-input`}>{t(challenge ? 'email_auth.code' : 'email_auth.email')}</label>
      <input key={challenge ? 'code' : 'email'} ref={input} id={`${id}-input`} type={challenge ? 'text' : 'email'} inputMode={challenge ? 'numeric' : 'email'} autoComplete={challenge ? 'one-time-code' : 'email'} autoCapitalize="none" spellCheck={false} required maxLength={challenge ? 6 : 254} pattern={challenge ? '[0-9]{6}' : undefined} className={challenge ? 'auth-code' : ''} value={challenge ? code : email} disabled={busy} aria-invalid={!!error} aria-describedby={`${id}-notice ${!challenge ? `${id}-hint` : ''}`} onChange={event => { if (challenge) setCode(event.target.value.replace(/\D/g, '').slice(0, 6)); else { setEmail(event.target.value); onEmailChange?.(event.target.value); } setError(''); }} />
      <div id={`${id}-notice`} className="auth-notice" aria-live="polite" role={error ? 'alert' : 'status'}>{error || notice}</div>
      <button className="auth-primary" disabled={busy || (!challenge && seconds > 0)}>{t(busy ? challenge ? 'email_auth.verifying' : 'email_auth.sending' : challenge ? binding ? 'email_auth.verify_bind' : 'email_auth.login' : 'email_auth.send')}{!challenge && seconds > 0 ? ` (${seconds}s)` : ''}</button>
    </form>
    {challenge ? <><div className="auth-resend"><span>{t(now >= Date.parse(challenge.expiresAt) ? 'email_auth.expired' : 'email_auth.valid_duration')}</span><button type="button" disabled={busy || seconds > 0} onClick={() => void send()}>{seconds > 0 ? t('email_auth.resend_wait', { seconds }) : t('email_auth.resend')}</button></div><details className="auth-help"><summary>{t('email_auth.help')}</summary><p>{t('email_auth.help_text')}{!binding && ` ${t('email_auth.help_apple')}`}</p></details></> : <p className="auth-hint" id={`${id}-hint`}>{t(binding ? 'email_auth.bind_hint' : 'email_auth.signup_hint')}</p>}
    {!challenge && !binding && <AuthTerms />}
  </section>;
}
