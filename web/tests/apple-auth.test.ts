import { authorizeApple } from '../src/auth/apple';
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });
function stub(signIn: (options: Record<string, unknown>) => Promise<unknown>) {
  let options: Record<string, unknown> = {};
  const init = vi.fn(value => { options = value; });
  vi.stubGlobal('window', { setTimeout, AppleID: { auth: { init, signIn: () => signIn(options) } } });
  return init;
}
it('passes binding nonce and unique state to Apple and returns only matching result', async () => {
  const init = stub(async options => ({ authorization: { id_token: 'token', state: options.state } }));
  await expect(authorizeApple(new AbortController().signal, 'server-nonce')).resolves.toEqual({ idToken: 'token', name: undefined });
  expect(init).toHaveBeenCalledWith(expect.objectContaining({ nonce:'server-nonce', state:expect.any(String), usePopup:true }));
});
it('rejects a mismatched authorization state', async () => {
  stub(async () => ({ authorization: { id_token:'token', state:'other-request' } }));
  await expect(authorizeApple(new AbortController().signal)).rejects.toThrow('apple_auth_failed');
});
it('cancels an outstanding popup and allows a subsequent attempt', async () => {
  stub(async () => new Promise(() => {}));
  const controller = new AbortController(); const pending = authorizeApple(controller.signal);
  await Promise.resolve(); controller.abort();
  await expect(pending).rejects.toMatchObject({ name:'AbortError' });
  stub(async () => { throw { error:'popup_closed_by_user' }; });
  await expect(authorizeApple(new AbortController().signal)).rejects.toThrow('apple_cancelled');
});
it('releases authorization immediately when cancelled during shared SDK loading', async () => {
  vi.useFakeTimers();
  const script = { remove: vi.fn(), onload: null as null | (() => void), onerror: null };
  const appendChild = vi.fn();
  vi.stubGlobal('document', { createElement: () => script, head: { appendChild } });
  vi.stubGlobal('window', { setTimeout });
  const controller = new AbortController();
  const first = authorizeApple(controller.signal).then(() => 'unexpected', error => error.name);
  controller.abort();
  await vi.advanceTimersByTimeAsync(0);
  // The shared script may still load, but the cancelled authorization must release the lock.
  stub(async () => { throw { error:'popup_closed_by_user' }; });
  const second = authorizeApple(new AbortController().signal).then(() => 'unexpected', error => error.message);
  script.onload?.();
  expect(await second).toBe('apple_cancelled');
  expect(await first).toBe('AbortError');
  expect(appendChild).toHaveBeenCalledTimes(1);
  vi.useRealTimers();
});
