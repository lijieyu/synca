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

for (const [name, response] of [
  ['old server', () => new Response('', {status:404})],
  ['HTML fallback', () => new Response('<html></html>')],
  ['disabled', () => new Response(JSON.stringify({email:false}))],
  ['malformed', () => new Response(JSON.stringify({email:'true'}))],
] as const) {
  it(`does not offer email on ${name}`, async () => {
    vi.stubGlobal('fetch', vi.fn(async () => response()));
    expect(await api.emailAvailable()).toBe(false);
  });
}
it('offers email only after an explicit server capability', async () => {
  vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({email:true}))));
  expect(await api.emailAvailable()).toBe(true);
});
it('preserves only a known legacy preview when capability endpoint is missing', async () => {
  vi.stubGlobal('fetch', vi.fn(async () => new Response('', {status:404})));
  expect(await api.emailAvailable(undefined, true)).toBe(true);
});
it('does not override an explicit disable or access denial even in preview', async () => {
  vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({email:false}))));
  expect(await api.emailAvailable(undefined, true)).toBe(false);
  vi.stubGlobal('fetch', vi.fn(async () => new Response('', {status:403})));
  expect(await api.emailAvailable(undefined, true)).toBe(false);
});
it('fails closed on network failure without touching the account session', async () => {
  const storage = {getItem:vi.fn(),removeItem:vi.fn()};
  vi.stubGlobal('localStorage', storage);
  vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('network failed'); }));
  expect(await api.emailAvailable()).toBe(false);
  expect(storage.getItem).not.toHaveBeenCalled();
  expect(storage.removeItem).not.toHaveBeenCalled();
});

it('identifies only opted-in desktop capability probes, leaving published Web unchanged',async()=>{
 const fetch=vi.fn(async()=>new Response(JSON.stringify({email:false})));
 vi.stubGlobal('fetch',fetch);
 vi.stubGlobal('window',{});
 await api.emailAvailable();
 expect(fetch.mock.calls[0]?.[1]).toEqual(expect.objectContaining({headers:{}}));
 vi.stubGlobal('window',{syncaDesktop:{emailAuth:true}});
 await api.emailAvailable();
 expect(fetch.mock.calls[1]?.[1]).toEqual(expect.objectContaining({headers:{'X-Synca-Client':'desktop'}}));
});
