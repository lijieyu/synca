import { api } from '../src/api/client';

afterEach(() => vi.unstubAllGlobals());
it('deletes only through the existing authenticated account endpoint', async () => {
  vi.stubGlobal('localStorage', { getItem: () => 'session' });
  const fetch = vi.fn(async () => new Response(JSON.stringify({ ok: true })));
  vi.stubGlobal('fetch', fetch);
  await expect(api.deleteAccount()).resolves.toEqual({ ok: true });
  expect(fetch).toHaveBeenCalledWith('/me/account', expect.objectContaining({ method: 'DELETE', headers: expect.objectContaining({ Authorization: 'Bearer session' }) }));
});
it('propagates account deletion failure so the account UI can retain the session', async () => {
  vi.stubGlobal('localStorage', { getItem: () => 'session' });
  vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: 'unavailable' }), { status: 503 })));
  await expect(api.deleteAccount()).rejects.toThrow();
});
