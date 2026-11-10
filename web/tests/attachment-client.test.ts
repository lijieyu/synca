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

  it('reuses display sources and revokes them on account reset', async () => {
    const revoke = vi.spyOn(URL, 'revokeObjectURL');
    vi.stubGlobal('fetch', vi.fn(async () => new Response(new Blob(['pixels'], { type: 'image/png' }))));
    await api.getProtectedFileBlob(url, { cacheImage: true });
    const source = api.cachedImageSource(url);
    expect(source).toMatch(/^blob:/);
    expect(api.cachedImageSource(url)).toBe(source);
    expect(api.cachedImageSource(url, '2000-01-01T00:00:00Z')).toBeNull();
    token = 'account-b';
    expect(api.cachedImageSource(url)).toBeNull();
    expect(revoke).toHaveBeenCalledWith(source);
    revoke.mockRestore();
  });

  it('never serves expired or invalid display sources', async () => {
    vi.useFakeTimers();
    vi.stubGlobal('fetch', vi.fn(async () => new Response(new Blob(['pixels'], { type: 'image/png' }))));
    await api.getProtectedFileBlob(url, { cacheImage: true });
    expect(api.cachedImageSource(url)).not.toBeNull();
    vi.advanceTimersByTime(60001);
    expect(api.cachedImageSource(url)).toBeNull();
    expect(api.cachedImageSource('http://[')).toBeNull();
    expect(api.cachedImageSource('https://other.test/api/media/a')).toBeNull();
  });

  it('displays the exact original after a successful large image upload without downloading', async () => {
    const file = new File([new Uint8Array(10 * 1024 * 1024)], 'original.png', { type: 'image/png' });
    const fetch = vi.fn(async () => Response.json({ imageUrl: url, type: 'image' }));
    vi.stubGlobal('fetch', fetch);
    const message = await api.sendImageMessage(file);
    const displayed = await api.getProtectedFileBlob(message.imageUrl!, { cacheImage: true });
    expect(displayed).toBe(file);
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it('does not seed failed uploads', async () => {
    const fetch = vi.fn().mockResolvedValueOnce(new Response('failed', { status: 500 }))
      .mockResolvedValue(new Response('server image'));
    vi.stubGlobal('fetch', fetch);
    await expect(api.sendImageMessage(new File(['original'], 'image.png', { type: 'image/png' }))).rejects.toThrow();
    expect(await (await api.getProtectedFileBlob(url, { cacheImage: true })).text()).toBe('server image');
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it.each(['switch', 'logout', 'reset'])('discards an upload completed after session %s', async action => {
    let finish!: (response: Response) => void;
    const fetch = vi.fn().mockImplementationOnce(() => new Promise<Response>(resolve => { finish = resolve; }))
      .mockResolvedValue(new Response('server image'));
    vi.stubGlobal('fetch', fetch);
    const pending = api.sendImageMessage(new File(['secret'], 'image.png', { type: 'image/png' }));
    if (action === 'switch') token = 'account-b';
    if (action === 'logout') token = null;
    if (action !== 'switch') api.resetSession();
    finish(Response.json({ imageUrl: url, type: 'image' }));
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    token = 'account-b';
    expect(await (await api.getProtectedFileBlob(url, { cacheImage: true })).text()).toBe('server image');
  });

  it.each(['switch', 'logout'])('clears a completed upload preview on %s', async action => {
    const fetch = vi.fn().mockResolvedValueOnce(Response.json({ imageUrl: url, type: 'image' }))
      .mockResolvedValue(new Response('server image'));
    vi.stubGlobal('fetch', fetch);
    const original = new File(['secret'], 'image.png', { type: 'image/png' });
    await api.sendImageMessage(original);
    if (action === 'logout') {
      token = null;
      api.resetSession();
      await expect(api.getProtectedFileBlob(url, { cacheImage: true })).rejects.toMatchObject({ name: 'AbortError' });
    }
    token = 'account-b';
    expect(await api.getProtectedFileBlob(url, { cacheImage: true })).not.toBe(original);
  });

  it('enforces the server retention deadline even without display metadata', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-22T00:00:00Z'));
    const fetch = vi.fn().mockResolvedValueOnce(Response.json({ imageUrl: url, type: 'image', attachmentExpiresAt: '2026-10-22T00:00:30Z' }))
      .mockResolvedValue(new Response('{"error":"attachment_expired"}', { status: 410 }));
    vi.stubGlobal('fetch', fetch);
    await api.sendImageMessage(new File(['original'], 'image.png', { type: 'image/png' }));
    vi.setSystemTime(new Date('2026-10-22T00:00:31Z'));
    await expect(api.getProtectedFileBlob(url, { cacheImage: true, expiresAt: '2026-10-22T00:00:30Z' })).rejects.toMatchObject({ code: 'attachment_expired' });
    expect(fetch).toHaveBeenCalledTimes(1);
    await expect(api.getProtectedFileBlob(url, { cacheImage: true })).rejects.toMatchObject({ code: 'attachment_expired' });
  });

  it('keeps only one uploaded original and expires it after 60 seconds', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-22T00:00:00Z'));
    const fetch = vi.fn().mockResolvedValueOnce(Response.json({ imageUrl: url, type: 'image' }))
      .mockResolvedValueOnce(Response.json({ imageUrl: `${url}?second`, type: 'image' }))
      .mockImplementation(async () => new Response('server image'));
    vi.stubGlobal('fetch', fetch);
    const original = new File(['original'], 'image.png', { type: 'image/png' });
    await api.sendImageMessage(original);
    await api.sendImageMessage(original);
    expect(await api.getProtectedFileBlob(`${url}?second`, { cacheImage: true })).toBe(original);
    expect(await api.getProtectedFileBlob(url, { cacheImage: true })).not.toBe(original);
    vi.advanceTimersByTime(60001);
    expect(await api.getProtectedFileBlob(`${url}?second`, { cacheImage: true })).not.toBe(original);
    expect(fetch).toHaveBeenCalledTimes(4);
  });

  it.each(['oversize', 'nonimage', 'origin', 'expired', 'invalid-expiry'])('does not seed unsafe or unsupported %s upload results', async kind => {
    const imageUrl = kind === 'origin' ? 'https://other.test/api/media/image.png' : url;
    const attachmentExpiresAt = kind === 'expired' ? '2000-01-01T00:00:00Z' : kind === 'invalid-expiry' ? 'invalid' : null;
    const fetch = vi.fn().mockResolvedValueOnce(Response.json({ imageUrl, type: 'image', attachmentExpiresAt }))
      .mockResolvedValue(new Response('server image'));
    vi.stubGlobal('fetch', fetch);
    const file = new File([new Uint8Array(kind === 'oversize' ? 20 * 1024 * 1024 + 1 : 1)], 'image.png',
      { type: kind === 'nonimage' ? 'application/pdf' : 'image/png' });
    await api.sendImageMessage(file);
    expect(await api.getProtectedFileBlob(url, { cacheImage: true })).not.toBe(file);
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it('seeds the progress upload path and keeps progress and cancellation working', async () => {
    let xhr: any;
    class Upload {
      upload = { onprogress: null as any };
      status = 200;
      responseText = JSON.stringify({ imageUrl: url, type: 'image' });
      onload!: () => void;
      onloadend!: () => void;
      onabort!: () => void;
      constructor() { xhr = this; }
      open() {}
      setRequestHeader() {}
      send() {}
      abort() { this.onabort(); this.onloadend(); }
    }
    vi.stubGlobal('XMLHttpRequest', Upload);
    const fetch = vi.fn();
    vi.stubGlobal('fetch', fetch);
    const file = new File(['original'], 'image.png', { type: 'image/png' });
    const onProgress = vi.fn();
    const pending = api.sendImageMessage(file, null, { signal: new AbortController().signal, onProgress });
    xhr.upload.onprogress({ lengthComputable: true, loaded: 1, total: 2 });
    expect(onProgress).toHaveBeenCalledWith(0.5);
    xhr.onload(); xhr.onloadend();
    await pending;
    expect(await api.getProtectedFileBlob(url, { cacheImage: true })).toBe(file);
    expect(fetch).not.toHaveBeenCalled();
    const controller = new AbortController();
    const cancelled = api.sendImageMessage(file, null, { signal: controller.signal, onProgress });
    controller.abort();
    await expect(cancelled).rejects.toMatchObject({ name: 'AbortError' });
  });

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
