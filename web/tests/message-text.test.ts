import { MESSAGE_TEXT_LIMIT, messageTextLength } from '../src/utils/messageText';
import { api } from '../src/api/client';

describe('message grapheme limit', () => {
  it.each(['字', '😀', '👍🏽', '👨‍👩‍👧‍👦', '🇨🇳', 'e\u0301', '\r\n'])('counts %s as one user-perceived character at both boundaries', glyph => {
    expect(messageTextLength(glyph.repeat(MESSAGE_TEXT_LIMIT))).toBe(10_000);
    expect(messageTextLength(glyph.repeat(MESSAGE_TEXT_LIMIT) + '字')).toBe(10_001);
  });
  it('counts mixed scripts and combining sequences without normalizing stored content', () => {
    expect(messageTextLength('中a😀e\u0301🇨🇳👨‍👩‍👧‍👦')).toBe(6);
    expect(messageTextLength('')).toBe(0);
  });
});

describe('long text transport', () => {
  beforeEach(() => {
    vi.stubGlobal('localStorage', { getItem: () => 'test-token', removeItem: vi.fn() });
    vi.stubGlobal('window', { location: { origin: 'https://synca.test', href: 'https://synca.test' } });
    api.resetSession();
  });
  afterEach(() => { api.resetSession(); vi.unstubAllGlobals(); });
  it('preserves a 10,000-grapheme message exactly when creating and editing', async () => {
    const text = '👨‍👩‍👧‍👦'.repeat(10_000);
    const fetch = vi.fn(async () => new Response(JSON.stringify({ id: 'record', textContent: text }), { headers: { 'Content-Type': 'application/json' } }));
    vi.stubGlobal('fetch', fetch);
    await api.sendTextMessage(text, 'category');
    await api.updateMessageText('record', text, '2026-11-08T00:00:00Z');
    expect(fetch).toHaveBeenCalledTimes(2);
    for (const call of fetch.mock.calls as unknown as [string, RequestInit][]) expect(JSON.parse(call[1].body as string).textContent).toBe(text);
  });
});
