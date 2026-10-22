import { api } from '../src/api/client';

describe('protected attachment lifecycle', () => {
  let token: string | null;
  const url = 'https://synca.test/api/media/example.png';
  beforeEach(() => {
    token = 'account-a';
    vi.stubGlobal('localStorage', { getItem: () => token, removeItem: () => { token = null; } });
    vi.stubGlobal('window', { location: { href: 'https://synca.test/', origin: 'https://synca.test', reload: vi.fn() } });
    api.resetSession();
  });
  afterEach(() => { api.resetSession(); vi.useRealTimers(); vi.unstubAllGlobals(); });

  it('never reads the legacy persistent attachment cache', async () => {
    const cache = { match: vi.fn(), put: vi.fn() };
    const storage = { open: vi.fn(async () => cache), delete: vi.fn(async () => true) };
    window.caches = storage;
    vi.stubGlobal('caches', storage);
    vi.stubGlobal('fetch', vi.fn(async () => new Response('download', { headers: { 'Content-Type': 'image/png' } })));
    api.resetSession();
    await api.getProtectedFileBlob(url);
    expect(storage.delete).toHaveBeenCalledWith('synca-attachment-cache-v1');
    expect(storage.open).not.toHaveBeenCalled();
  });

  it('reuses a small image in memory but rejects it at its retention deadline', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-22T00:00:00Z'));
    const fetch = vi.fn(async () => new Response('image', { headers: { 'Content-Type': 'image/png' } }));
    vi.stubGlobal('fetch', fetch);
    const options = { cacheImage: true, expiresAt: '2026-10-22T00:00:30Z' };
    await api.getProtectedFileBlob(url, options);
    await api.getProtectedFileBlob(url, options);
    expect(fetch).toHaveBeenCalledTimes(1);
    vi.setSystemTime(new Date('2026-10-22T00:00:31Z'));
    await expect(api.getProtectedFileBlob(url, options)).rejects.toMatchObject({ code: 'attachment_expired' });
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it('does not expose a cached image to another account', async () => {
    const fetch = vi.fn(async () => new Response('image', { headers: { 'Content-Type': 'image/png' } }));
    vi.stubGlobal('fetch', fetch);
    await api.getProtectedFileBlob(url, { cacheImage: true });
    token = 'account-b';
    await api.getProtectedFileBlob(url, { cacheImage: true });
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(fetch.mock.calls[1][1].headers.Authorization).toBe('Bearer account-b');
  });

  it('discards a download whose account changed while reading the body', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, blob: async () => { token = 'account-b'; return new Blob(['secret']); } })));
    await expect(api.getProtectedFileBlob(url)).rejects.toMatchObject({ name: 'AbortError' });
  });

  it('checks expired server responses even when local metadata is stale', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{"error":"attachment_expired"}', { status: 410 })));
    await expect(api.getProtectedFileBlob(url)).rejects.toMatchObject({ code: 'attachment_expired' });
  });

  it('never sends authorization to another origin or follows redirects', async () => {
    const fetch = vi.fn(async () => new Response('file'));
    vi.stubGlobal('fetch', fetch);
    await expect(api.getProtectedFileBlob('https://other.test/api/media/image')).rejects.toThrow('Invalid attachment URL');
    expect(fetch).not.toHaveBeenCalled();
    await api.getProtectedFileBlob(url);
    expect(fetch.mock.calls[0][1]).toMatchObject({ cache: 'no-store', redirect: 'error' });
  });

  it('does not keep ordinary files or large images in the image cache', async () => {
    const fetch = vi.fn(async () => new Response(new Uint8Array(4 * 1024 * 1024 + 1), { headers: { 'Content-Type': 'image/png' } }));
    vi.stubGlobal('fetch', fetch);
    await api.getProtectedFileBlob(url, { cacheImage: true });
    await api.getProtectedFileBlob(url, { cacheImage: true });
    expect(fetch).toHaveBeenCalledTimes(2);
    fetch.mockImplementation(async () => new Response('PDF', { headers: { 'Content-Type': 'application/pdf' } }));
    await api.getProtectedFileBlob(url, { cacheImage: true });
    await api.getProtectedFileBlob(url, { cacheImage: true });
    expect(fetch).toHaveBeenCalledTimes(4);
  });

  it('evicts the oldest images once the 16 MB memory budget is reached', async () => {
    const fetch = vi.fn(async () => new Response(new Uint8Array(4 * 1024 * 1024), { headers: { 'Content-Type': 'image/png' } }));
    vi.stubGlobal('fetch', fetch);
    for (let i = 0; i < 5; i++) await api.getProtectedFileBlob(`${url}?${i}`, { cacheImage: true });
    await api.getProtectedFileBlob(`${url}?4`, { cacheImage: true });
    expect(fetch).toHaveBeenCalledTimes(5);
    await api.getProtectedFileBlob(`${url}?0`, { cacheImage: true });
    expect(fetch).toHaveBeenCalledTimes(6);
  });

  it('cancels a protected download immediately on sign-out', async () => {
    let started: () => void;
    const ready = new Promise<void>(resolve => { started = resolve; });
    vi.stubGlobal('fetch', vi.fn((_url, options) => new Promise((_resolve, reject) => {
      options.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));
      started();
    })));
    const pending = api.getProtectedFileBlob(url);
    const assertion = expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    await ready;
    token = null;
    api.resetSession();
    await assertion;
  });
});
