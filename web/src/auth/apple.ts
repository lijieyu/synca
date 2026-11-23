interface AppleResult { authorization: { id_token: string; state: string }; user?: { name?: { firstName?: string; lastName?: string } } }
interface AppleSDK { auth: { init(options: Record<string, unknown>): void; signIn(): Promise<AppleResult> } }
let loading: Promise<AppleSDK> | undefined;
let active = false;
const sdk = () => (window as Window & { AppleID?: AppleSDK }).AppleID;
export function loadApple(): Promise<AppleSDK> {
  if (sdk()) return Promise.resolve(sdk()!);
  if (!loading) loading = new Promise<AppleSDK>((resolve, reject) => {
    const script = document.createElement('script');
    const timer = window.setTimeout(() => fail(), 15000);
    const fail = () => { clearTimeout(timer); script.remove(); loading = undefined; reject(new Error('apple_unavailable')); };
    script.src = 'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';
    script.async = true;
    script.onload = () => { clearTimeout(timer); if (sdk()) resolve(sdk()!); else fail(); };
    script.onerror = fail;
    document.head.appendChild(script);
  });
  return loading;
}
export async function authorizeApple(signal: AbortSignal, nonce?: string) {
  if (active) throw new Error('apple_busy');
  active = true;
  let timer: number | undefined;
  let abort: (() => void) | undefined;
  try {
    signal.throwIfAborted();
    const cancelled = new Promise<never>((_, reject) => {
      abort = () => reject(new DOMException('Cancelled', 'AbortError'));
      signal.addEventListener('abort', abort, { once: true });
    });
    const apple = await Promise.race([loadApple(), cancelled]);
    signal.throwIfAborted();
    const state = crypto.randomUUID();
    apple.auth.init({ clientId: 'cn.haerth.synca.web', scope: 'name email', redirectURI: 'https://synca.haerth.cn/api/auth/apple/callback', usePopup: true, state, nonce: nonce ?? crypto.randomUUID() });
    const result = await Promise.race([apple.auth.signIn(), cancelled, new Promise<never>((_, reject) => {
      timer = window.setTimeout(() => reject(new Error('apple_timeout')), 120000);
    })]);
    signal.throwIfAborted();
    if (result.authorization?.state !== state || !result.authorization.id_token) throw new Error('apple_auth_failed');
    const { firstName, lastName } = result.user?.name ?? {};
    const joined = [firstName, lastName].filter(Boolean).join(' ');
    return { idToken: result.authorization.id_token, name: /[\u4e00-\u9fa5]/.test(joined) ? [lastName, firstName].filter(Boolean).join('') : joined || undefined };
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    const code = (error as { error?: string }).error;
    throw new Error(code === 'user_cancelled_authorize' || code === 'popup_closed_by_user' ? 'apple_cancelled' : error instanceof Error ? error.message : 'apple_auth_failed');
  } finally {
    active = false;
    clearTimeout(timer);
    if (abort) signal.removeEventListener('abort', abort);
  }
}
