import { createHash } from 'node:crypto';
import type { Request, Response } from 'express';
import { sql } from 'kysely';
import { db } from './db.js';
import { buildAccessStatus } from './access.js';
import { listMessageCategories } from './store.js';
import { getUserIdFromToken } from './auth.js';

const HEARTBEAT_MS = 25_000;
const MAX_ACCOUNT_STREAMS = 12;
const MAX_STREAMS = 1000;
const streams = new Map<string, Set<Response>>();
const pending = new Map<string, NodeJS.Timeout>();
const cleanup = new Map<Response, () => void>();
const hash = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex').slice(0, 24);

// Small anti-entropy snapshot. Hashes are durable across process restarts and also
// detect maintenance writes and time-dependent entitlement changes without a broker.
export async function syncState(userId: string) {
    const [record, categories, access] = await Promise.all([
        sql<{ latest: string | null; total: number; count: number }>`SELECT MAX(updated_at) AS latest, COUNT(*) AS total,
          COALESCE(SUM(CASE WHEN is_deleted=0 AND is_cleared=0 THEN 1 ELSE 0 END),0) AS count
          FROM messages WHERE user_id=${userId}`.execute(db),
        listMessageCategories(userId), buildAccessStatus(userId),
    ]);
    const row = record.rows[0];
    return { messages: hash(row), categories: hash(categories), access: hash(access), latestMessage: row.latest, count: Number(row.count) };
}
function send(response: Response, text: string) {
    // A stalled client cannot accumulate unbounded response buffers.
    if (response.destroyed || !response.write(text)) response.destroy();
}
export function notifySync(userId: string) {
    if (!streams.has(userId) || pending.has(userId)) return;
    const timer = setTimeout(() => {
        pending.delete(userId);
        for (const response of streams.get(userId) ?? []) send(response, 'event: change\ndata: {}\n\n');
    }, 100);
    timer.unref(); pending.set(userId, timer);
}
export function openSyncStream(req: Request, res: Response, userId: string) {
    const account = streams.get(userId) ?? new Set<Response>();
    if (account.size >= MAX_ACCOUNT_STREAMS || cleanup.size >= MAX_STREAMS) {
        res.set('Retry-After', '60').status(429).json({ error: 'too_many_sync_connections' }); return;
    }
    res.status(200).set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', 'X-Accel-Buffering': 'no' });
    res.flushHeaders();
    account.add(res); streams.set(userId, account);
    let checking = false;
    const timer = setInterval(async () => {
        if (checking) return;
        checking = true;
        try {
            // Revoked sessions must not keep an authenticated stream indefinitely.
            if (await getUserIdFromToken(req.header('Authorization')) !== userId) { res.end(); return; }
            send(res, ': heartbeat\n\n');
        } catch { res.end(); }
        finally { checking = false; }
    }, HEARTBEAT_MS);
    timer.unref();
    const close = () => {
        clearInterval(timer); account.delete(res); cleanup.delete(res);
        if (!account.size) { streams.delete(userId); clearTimeout(pending.get(userId)); pending.delete(userId); }
    };
    cleanup.set(res, close); res.once('close', close);
    // Subscribe BEFORE the initial hint: every reconnect catches missed writes.
    send(res, 'retry: 3000\nevent: change\ndata: {}\n\n');
}
export function closeSyncStreams() {
    for (const [res, close] of cleanup) { close(); res.end(); }
    for (const timer of pending.values()) clearTimeout(timer);
    pending.clear();
}
