import { sql } from 'kysely';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import type { RequestHandler } from 'express';
import { db } from './db.js';
import { getMessage, purgeMessageMedia } from './store.js';
import { assertCanCreateMessage, DailyLimitError } from './access.js';

import { storagePolicy, IMAGE_LIMIT, FILE_LIMIT } from './storagePolicy.js';
export { storagePolicy, storageUsage, IMAGE_LIMIT, FILE_LIMIT } from './storagePolicy.js';

// The conditional INSERT is one SQLite statement: simultaneous uploads cannot overbook capacity.
export async function reserveUpload(userId: string, bytes: number, capacity: number, kind: string, id: string = randomUUID()) {
    const expires = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    const result = await sql`INSERT INTO upload_reservations(id,user_id,bytes,expires_at,kind)
        SELECT ${id},${userId},${bytes},${expires},${kind}
        WHERE (SELECT COALESCE(SUM(file_size),0) FROM messages WHERE user_id=${userId}
            AND is_deleted=0 AND attachment_purged=0 AND type IN ('image','file'))
          + (SELECT COALESCE(SUM(bytes),0) FROM upload_reservations WHERE user_id=${userId})
          + ${bytes} <= ${capacity}
          AND (SELECT COUNT(*) FROM upload_reservations WHERE user_id=${userId}) < 4
          ON CONFLICT(id) DO NOTHING`.execute(db);
    return result.numAffectedRows === 1n ? id : null;
}

export const prepareUpload = (kind: 'image' | 'file'): RequestHandler => async (req, res, next) => {
    try {
        const userId = (req as any).userId as string;
        const uploadID = req.header('X-Upload-ID') ?? randomUUID();
        if (!/^[0-9a-f-]{36}$/i.test(uploadID)) { res.status(400).json({ error: 'invalid_upload_id' }); return; }
        const previous = await getMessage(uploadID, `${req.protocol}://${req.get('host')}`);
        if (previous) {
            if (previous.userId !== userId || previous.type !== kind) { res.status(409).json({ error: 'invalid_upload_id' }); return; }
            res.status(201).json(previous); return;
        }
        const status = await assertCanCreateMessage(userId);
        const policy = storagePolicy(status.isUnlimited);
        if (kind === 'file' && !policy.canUploadFiles) {
            res.status(403).json({ error: 'file_upload_requires_paid', accessStatus: status }); return;
        }
        const maximum = kind === 'image' ? IMAGE_LIMIT : FILE_LIMIT;
        const header = req.header('X-Upload-Size');
        const bytes = header === undefined ? maximum : Number(header);
        if (!Number.isSafeInteger(bytes) || bytes < 1 || bytes > maximum) {
            res.status(413).json({ error: 'file_too_large', limitBytes: maximum }); return;
        }
        const reservationId = await reserveUpload(userId, bytes, policy.limitBytes, kind, uploadID);
        if (!reservationId) { res.status(413).json({ error: 'storage_limit_reached' }); return; }
        res.locals.upload = { reservationId, messageId: uploadID, bytes, retentionDays: policy.retentionDays };
        // Multer has bounded disk streaming; a crash is recovered by the reservation sweeper.
        const deadline = setTimeout(() => req.destroy(), 15 * 60 * 1000);
        deadline.unref();
        res.once('close', () => clearTimeout(deadline));
        req.setTimeout(15 * 60 * 1000, () => req.destroy());
        res.once('close', () => { if (!res.locals.upload.processing) void releaseUpload(reservationId).catch(console.error); });
        next();
    } catch (error) {
        if (error instanceof DailyLimitError) res.status(403).json({ error: 'daily_limit_reached', accessStatus: error.accessStatus });
        else next(error);
    }
};

export async function trackUpload(id: string, filename: string) {
    const result = await sql`UPDATE upload_reservations SET filename=${filename} WHERE id=${id} AND expires_at > ${new Date().toISOString()}`.execute(db);
    if (result.numAffectedRows !== 1n) throw new Error('upload_cancelled');
}
async function unlinkMedia(kind: string, filename: string) {
    if (path.basename(filename) !== filename) throw new Error('invalid_media_path');
    const directory = kind === 'image' ? 'uploads' : kind === 'file' ? 'files' : kind === 'feedback' ? 'feedback_uploads' : null;
    if (!directory) throw new Error('invalid_media_kind');
    try { await fs.unlink(path.resolve(directory, filename)); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
}
export async function releaseUpload(id: string, expiredBy?: string) {
    const expiryCondition = expiredBy ? sql`AND expires_at <= ${expiredBy}` : sql``;
    const row = (await sql<{ filename: string | null; kind: string }>`UPDATE upload_reservations
        SET expires_at='1970-01-01T00:00:00.000Z' WHERE id=${id} ${expiryCondition} RETURNING filename,kind`.execute(db)).rows[0];
    if (!row) return; // Successful commit consumed the reservation atomically.
    if (row.filename) await unlinkMedia(row.kind, row.filename);
    // Another cleanup can finish first and a retry may reuse the upload ID.
    // Never delete that retry's new reservation after our unlink completes.
    await sql`DELETE FROM upload_reservations WHERE id=${id}
        AND expires_at='1970-01-01T00:00:00.000Z' AND filename IS ${row.filename}`.execute(db);
}
let cleaning = false;
export async function cleanupExpiredAttachments(now = new Date()) {
    if (cleaning) return;
    cleaning = true;
    try {
        const rows = await db.selectFrom('messages').selectAll().where('attachment_purged', '=', 0)
            .where('attachment_expires_at', '<=', now.toISOString()).limit(200).execute();
        for (const row of rows) {
            try {
                await purgeMessageMedia(row, path.resolve('uploads'), path.resolve('files'), now.toISOString());
            } catch (error) { console.error('[storage] cleanup retry required', row.id, error); }
        }
        const stale = await sql<{ id: string }>`SELECT id FROM upload_reservations WHERE expires_at <= ${now.toISOString()} LIMIT 200`.execute(db);
        for (const row of stale.rows) {
            try { await releaseUpload(row.id, now.toISOString()); }
            catch (error) { console.error('[storage] Upload cleanup retry required', row.id, error); }
        }
    } finally { cleaning = false; }
}
