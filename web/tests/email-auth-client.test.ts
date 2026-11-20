import { api } from '../src/api/client';
afterEach(() => vi.unstubAllGlobals());
it('keeps invalid anonymous verification inline without reloading or deleting session', async () => {
  const removeItem = vi.fn(); const reload = vi.fn();
  vi.stubGlobal('localStorage', { getItem: () => null, removeItem });
  vi.stubGlobal('window', { location: { reload } });
  vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: 'invalid_code' }), { status: 401 })));
  await expect(api.verifyEmailCode('challenge', '000000')).rejects.toMatchObject({ code: 'invalid_code' });
  expect(removeItem).not.toHaveBeenCalled(); expect(reload).not.toHaveBeenCalled();
});
it('uses the authenticated binding endpoint without exchanging the session', async () => {
  vi.stubGlobal('localStorage', { getItem: () => 'session' });
  const fetch = vi.fn(async () => new Response(JSON.stringify({ apple: true, email: 'a@example.com' })));
  vi.stubGlobal('fetch', fetch);
  await api.bindEmail('challenge', '123456');
  expect(fetch).toHaveBeenCalledWith('/me/login-methods/email/verify', expect.objectContaining({ body: JSON.stringify({ challengeId: 'challenge', code: '123456' }), headers: expect.objectContaining({ Authorization: 'Bearer session' }) }));
});
it('expires a real session when a binding request is unauthorized', async () => {
  let token: string | null = 'session'; const reload = vi.fn();
  vi.stubGlobal('localStorage', { getItem: () => token, removeItem: () => { token = null; } });
  vi.stubGlobal('window', { location: { reload } });
  vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 })));
  await expect(api.bindEmail('challenge','123456')).rejects.toThrow('Unauthorized');
  expect(token).toBeNull(); expect(reload).toHaveBeenCalledOnce();
});
it('discards an old session binding response after account switching', async () => {
  let token = 'old-session';
  vi.stubGlobal('localStorage', { getItem: () => token });
  vi.stubGlobal('fetch', vi.fn(async () => { token = 'new-session'; return new Response(JSON.stringify({ apple: true, email: 'old@example.com' })); }));
  await expect(api.bindEmail('challenge', '123456')).rejects.toMatchObject({ name:'AbortError' });
});
