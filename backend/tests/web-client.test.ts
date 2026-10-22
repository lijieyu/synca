import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api, DailyLimitError } from '../../web/src/api/client';

describe('Web API session and upload contracts', () => {
  let values: Map<string, string>;
  let reload: ReturnType<typeof vi.fn>;
  beforeEach(() => {
    values = new Map([['authToken', 'old-account']]);
    reload = vi.fn();
    vi.stubGlobal('localStorage', {
      getItem: (key: string) => values.get(key) ?? null,
      removeItem: (key: string) => values.delete(key),
    });
    vi.stubGlobal('window', { location: { reload } });
  });
  afterEach(() => vi.unstubAllGlobals());

  it('does not sign out a new account on an old 401 response', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => {
      values.set('authToken', 'new-account');
      return new Response('{}', { status: 401 });
    }));
    await expect(api.listMessages()).rejects.toMatchObject({ name: 'AbortError' });
    expect(values.get('authToken')).toBe('new-account');
    expect(reload).not.toHaveBeenCalled();
  });

  it('discards old data if the account changes during decoding', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, status: 200, json: async () => {
      values.set('authToken', 'new-account');
      return { messages: [{ id: 'private-old-data' }] };
    } })));
    await expect(api.listMessages()).rejects.toMatchObject({ name: 'AbortError' });
  });

  it('handles expired sessions consistently for image uploads', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{}', { status: 401 })));
    await expect(api.sendImageMessage(new File(['image'], 'test.png'))).rejects.toThrow('Unauthorized');
    expect(values.has('authToken')).toBe(false);
    expect(reload).toHaveBeenCalledOnce();
  });

  it('preserves daily-limit errors for both attachment types', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{"error":"daily_limit_reached"}', { status: 403 })));
    const file = new File(['content'], 'test.txt');
    await expect(api.sendFileMessage(file)).rejects.toBeInstanceOf(DailyLimitError);
    await expect(api.sendImageMessage(file)).rejects.toBeInstanceOf(DailyLimitError);
  });

  it('preserves multipart boundaries, category and authentication', async () => {
    const fetchMock = vi.fn(async (_url: string, _options: RequestInit) => new Response('{"id":"sent"}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    await expect(api.sendFileMessage(new File(['content'], 'test.txt'), 'category')).resolves.toEqual({ id: 'sent' });
    const options = fetchMock.mock.calls[0][1];
    expect(options.headers).toMatchObject({ Authorization: 'Bearer old-account', 'X-Upload-Size': '7' });
    expect((options.headers as Record<string,string>)['Content-Type']).toBeUndefined();
    expect((options.body as FormData).get('categoryId')).toBe('category');
  });
  it('preserves specific capacity and paid-file errors', async () => {
    for (const code of ['storage_limit_reached', 'file_upload_requires_paid', 'attachment_expired']) {
      vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({error:code}), {status:413})));
      await expect(api.sendFileMessage(new File(['test'], 'test.pdf'))).rejects.toMatchObject({code});
    }
  });
  it('reuses an upload ID for a retry of the same selected file', async () => {
    const fetchMock = vi.fn(async (_url: string, _options: RequestInit) => new Response('{"id":"same-message"}'));
    vi.stubGlobal('fetch', fetchMock);
    const file = new File(['test'], 'test.pdf');
    await api.sendFileMessage(file); await api.sendFileMessage(file);
    expect((fetchMock.mock.calls[0][1].headers as Record<string,string>)['X-Upload-ID'])
      .toBe((fetchMock.mock.calls[1][1].headers as Record<string,string>)['X-Upload-ID']);
  });

});
