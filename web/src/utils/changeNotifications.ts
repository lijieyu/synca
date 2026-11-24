export interface ChangeOptions {
  token: string;
  onChange: () => Promise<boolean>;
  onUnauthorized?: () => void;
  fetcher?: typeof fetch;
  base?: string;
  stream?: boolean;
  interval?: number;
  retry?: number;
}
/** One bounded transport/scheduler for Web and the Electron main process.
 * Hints are invalidations, not data. A failed or blocked consumer stays dirty.
 */
export function createChangeNotifications(options: ChangeOptions) {
  const fetcher = options.fetcher ?? fetch;
  const retry = options.retry ?? 1000;
  let stopped = false, dirty = false, running = false;
  let retryDelay = retry, reconnectDelay = retry;
  let workTimer: ReturnType<typeof setTimeout> | undefined;
  let connectTimer: ReturnType<typeof setTimeout> | undefined;
  let controller: AbortController | undefined;
  let idleTimer: ReturnType<typeof setTimeout> | undefined;
  const schedule = (delay = 0) => {
    if (stopped || running || workTimer) return;
    workTimer = setTimeout(() => { workTimer = undefined; void flush(); }, delay);
  };
  async function flush() {
    if (stopped || running || !dirty) return;
    running = true; dirty = false;
    let ok = false;
    try { ok = await options.onChange(); } catch { /* Retry without losing dirty state. */ }
    running = false;
    if (stopped) return;
    if (!ok) { dirty = true; schedule(retryDelay); retryDelay = Math.min(retryDelay * 2, 60_000); }
    else { retryDelay = retry; if (dirty) schedule(); }
  }
  function hint() { if (!stopped) { dirty = true; schedule(); } }
  function stop() {
    stopped = true; dirty = false;
    clearTimeout(workTimer); clearTimeout(connectTimer); clearTimeout(idleTimer); clearInterval(checkTimer);
    controller?.abort();
  }
  async function connect() {
    if (stopped) return;
    controller = new AbortController();
    const abort = controller;
    const touch = () => { clearTimeout(idleTimer); idleTimer = setTimeout(() => abort.abort(), 65_000); };
    touch();
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      const response = await fetcher((options.base ?? '') + '/sync/events', {
        headers: { Authorization: 'Bearer ' + options.token, Accept: 'text/event-stream' },
        cache: 'no-store', redirect: 'error', signal: abort.signal,
      });
      if (response.status === 401 || response.status === 403) { stop(); options.onUnauthorized?.(); return; }
      if (!response.ok || !response.headers.get('content-type')?.includes('text/event-stream') || !response.body) throw Error('Sync stream unavailable');
      reader = response.body.getReader();
      const decoder = new TextDecoder(); let buffer = '';
      while (!stopped) {
        const result = await reader.read();
        if (result.done) break;
        touch(); buffer += decoder.decode(result.value, { stream: true }).replace(/\r/g, '');
        if (buffer.length > 16_384) throw Error('Invalid sync frame');
        let end: number;
        while ((end = buffer.indexOf('\n\n')) !== -1) {
          const frame = buffer.slice(0, end); buffer = buffer.slice(end + 2);
          if (/^event: change$/m.test(frame)) hint();
          // Only a live heartbeat resets backoff; repeated short-lived streams don't spin.
          if (frame.startsWith(': heartbeat')) reconnectDelay = retry;
        }
      }
    } catch { /* A reconnect always receives an initial catch-up hint. */ }
    finally {
      clearTimeout(idleTimer); abort.abort();
      void reader?.cancel().catch(() => {});
      if (!stopped) {
        const delay = reconnectDelay + Math.random() * Math.min(reconnectDelay / 4, 1000);
        reconnectDelay = Math.min(reconnectDelay * 2, 60_000);
        connectTimer = setTimeout(() => void connect(), delay);
      }
    }
  }
  const checkTimer = setInterval(hint, options.interval ?? 300_000);
  hint();
  if (options.stream !== false) void connect();
  return { hint, stop };
}
