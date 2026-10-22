import { beforeAll, beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { sql } from 'kysely';
import app from '../src/app.js';
import { db } from '../src/db.js';
import { runMigrations } from '../src/migrate.js';
import { resetDb, createSession, createMessage } from '../src/store.js';
import { reserveUpload, releaseUpload, storagePolicy, storageUsage, cleanupExpiredAttachments, FILE_LIMIT, IMAGE_LIMIT, trackUpload } from '../src/storage.js';

async function account(paid = false) {
    const id = randomUUID(), token = randomUUID(), now = new Date().toISOString();
    await db.insertInto('users').values({ id, apple_user_id: id, email: 'storage@example.com', nickname: 'Storage',
        lifetime_purchased_at: paid ? now : null, created_at: now, updated_at: now }).execute();
    await createSession(token, id);
    return { id, auth: `Bearer ${token}` };
}
const createdFiles: string[] = [];
function remember(message: any) {
    if (message.imagePath) createdFiles.push(path.resolve('uploads', message.imagePath));
    if (message.filePath) createdFiles.push(path.resolve('files', message.filePath));
}

describe('Attachment storage contract', () => {
    beforeAll(runMigrations);
    beforeEach(resetDb);
    afterEach(async () => {
        vi.restoreAllMocks();
        for (const file of createdFiles.splice(0)) await fs.rm(file, { force: true });
    });
    it('publishes identical limits for clients', async () => {
        for (const paid of [false, true]) {
            const user = await account(paid);
            const res = await request(app).get('/me/access-status').set('Authorization', user.auth);
            expect(res.body.accessStatus.storage).toEqual({ ...storagePolicy(paid), usedBytes: 0 });
        }
        expect(IMAGE_LIMIT).toBe(50 * 1024 * 1024);
        expect(FILE_LIMIT).toBe(200 * 1024 * 1024);
    });
    it('rejects free file uploads before accepting a body', async () => {
        const user = await account();
        const res = await request(app).post('/messages/file').set('Authorization', user.auth);
        expect(res.status).toBe(403);
        expect(res.body.error).toBe('file_upload_requires_paid');
    });
    it('enforces the final free daily slot atomically across concurrent clients', async () => {
        const user = await account();
        for (let index = 0; index < 19; index++) {
            const response = await request(app).post('/messages').set('Authorization', user.auth).send({ textContent: `message ${index}` });
            expect(response.status).toBe(201);
        }
        const responses = await Promise.all(Array.from({ length: 8 }, () =>
            request(app).post('/messages').set('Authorization', user.auth).send({ textContent: 'last slot' })));
        expect(responses.filter(response => response.status === 201)).toHaveLength(1);
        expect(responses.filter(response => response.status !== 201).map(response => ({ status: response.status, error: response.body.error })))
            .toEqual(Array.from({ length: 7 }, () => ({ status: 403, error: 'daily_limit_reached' })));
        const status = await request(app).get('/me/access-status').set('Authorization', user.auth);
        expect(status.body.accessStatus.todayUsed).toBe(20);
    });
    it('blocks uploads finishing after paid access expires and keeps the transaction atomic', async () => {
        const user = await account(true), id = randomUUID();
        await reserveUpload(user.id, 4, storagePolicy(true).limitBytes, 'file', id);
        await db.updateTable('users').set({ lifetime_purchased_at: null }).where('id', '=', user.id).execute();
        await expect(createMessage({ id, userId: user.id, type: 'file', fileSize: 4, filePath: 'unused.pdf',
            reservationId: id, now: new Date().toISOString() })).rejects.toMatchObject({ code: 'file_upload_requires_paid' });
        expect(await db.selectFrom('messages').select('id').execute()).toHaveLength(0);
        await releaseUpload(id);
    });
    it('invalidates in-flight uploads on account deletion and cleans their disk files', async () => {
        const user = await account(true), id = randomUUID(), filename = `storage-test-${randomUUID()}.pdf`;
        const file = path.resolve('files', filename); createdFiles.push(file);
        await reserveUpload(user.id, 4, storagePolicy(true).limitBytes, 'file', id);
        await fs.writeFile(file, 'test'); await trackUpload(id, filename);
        expect((await request(app).delete('/me/account').set('Authorization', user.auth)).status).toBe(200);
        await expect(createMessage({ id, userId: user.id, type: 'file', fileSize: 4, filePath: filename,
            reservationId: id, now: new Date().toISOString() })).rejects.toMatchObject({ code: 'unauthorized' });
        expect(await db.selectFrom('message_categories').select('id').execute()).toHaveLength(0);
        await cleanupExpiredAttachments();
        await expect(fs.stat(file)).rejects.toMatchObject({ code: 'ENOENT' });
        expect((await sql`SELECT * FROM upload_reservations`.execute(db)).rows).toHaveLength(0);
    });
    it('retries account media removal even after its account and messages are gone', async () => {
        const user = await account(true);
        const response = await request(app).post('/messages/file').set('Authorization', user.auth)
            .set('X-Upload-Size', '4').attach('file', Buffer.from('test'), 'test.pdf');
        remember(response.body); expect(response.status).toBe(201);
        const unlink = vi.spyOn(fs, 'unlink').mockRejectedValueOnce(Object.assign(new Error('disk busy'), { code: 'EBUSY' }));
        vi.spyOn(console, 'error').mockImplementation(() => {});
        expect((await request(app).delete('/me/account').set('Authorization', user.auth)).status).toBe(200);
        expect(await db.selectFrom('users').select('id').execute()).toHaveLength(0);
        expect(await db.selectFrom('messages').select('id').execute()).toHaveLength(0);
        expect((await sql`SELECT filename FROM upload_reservations`.execute(db)).rows).toEqual([{ filename: response.body.filePath }]);
        unlink.mockRestore();
        await cleanupExpiredAttachments();
        await expect(fs.stat(path.resolve('files', response.body.filePath))).rejects.toMatchObject({ code: 'ENOENT' });
        expect((await sql`SELECT * FROM upload_reservations`.execute(db)).rows).toHaveLength(0);
    });
    it('requires the reservation to belong to the same account and cover the actual size', async () => {
        const owner = await account(true), other = await account(true), id = randomUUID();
        await reserveUpload(owner.id, 4, storagePolicy(true).limitBytes, 'file', id);
        for (const [userId, fileSize] of [[other.id, 4], [owner.id, 5]] as const) {
            await expect(createMessage({ id, userId, type: 'file', fileSize, filePath: 'unused.pdf',
                reservationId: id, now: new Date().toISOString() })).rejects.toMatchObject({ code: 'upload_cancelled' });
        }
        expect(await db.selectFrom('messages').select('id').execute()).toHaveLength(0);
        await releaseUpload(id);
    });
    it('keeps a failed deletion retryable without exposing the deleted attachment', async () => {
        const user = await account(true);
        const res = await request(app).post('/messages/file').set('Authorization', user.auth)
            .set('X-Upload-Size', '4').attach('file', Buffer.from('test'), 'test.pdf');
        remember(res.body); expect(res.status).toBe(201);
        const unlink = vi.spyOn(fs, 'unlink').mockRejectedValueOnce(Object.assign(new Error('disk busy'), { code: 'EBUSY' }));
        vi.spyOn(console, 'error').mockImplementation(() => {});
        expect((await request(app).delete(`/messages/${res.body.id}`).set('Authorization', user.auth)).status).toBe(200);
        const row = await db.selectFrom('messages').selectAll().where('id', '=', res.body.id).executeTakeFirstOrThrow();
        expect(row).toMatchObject({ is_deleted: 1, attachment_purged: 0, file_path: res.body.filePath });
        expect((await request(app).get(`/api/media/${res.body.filePath}`).set('Authorization', user.auth)).status).toBe(410);
        const list = await request(app).get('/messages?since=2000-01-01T00:00:00.000Z').set('Authorization', user.auth);
        expect(list.body.messages[0].filePath).toBeUndefined();
        expect(list.body.messages[0].fileUrl).toBeUndefined();
        unlink.mockRestore();
        await cleanupExpiredAttachments();
        await expect(fs.stat(path.resolve('files', res.body.filePath))).rejects.toMatchObject({ code: 'ENOENT' });
        const purged = await db.selectFrom('messages').selectAll().where('id', '=', res.body.id).executeTakeFirstOrThrow();
        expect(purged).toMatchObject({ attachment_purged: 1, file_path: null });
    });
    it('requires owner authentication and serves documents as non-sniffable downloads', async () => {
        const owner = await account(true), other = await account(true);
        const res = await request(app).post('/messages/file').set('Authorization', owner.auth)
            .set('X-Upload-Size', '4').attach('file', Buffer.from('test'), 'test.pdf');
        remember(res.body); expect(res.status).toBe(201);
        const url = `/api/media/${res.body.filePath}`;
        expect((await request(app).get(url)).status).toBe(401);
        expect((await request(app).get(url).set('Authorization', other.auth)).status).toBe(403);
        const download = await request(app).get(url).set('Authorization', owner.auth);
        expect(download.status).toBe(200);
        expect(download.headers['content-disposition']).toMatch(/^attachment;/);
        expect(download.headers['x-content-type-options']).toBe('nosniff');
        expect(download.headers['cache-control']).toBe('private, no-store');
    });
    it('rejects malformed multipart metadata without retaining files or capacity', async () => {
        const user = await account(true);
        const result = await request(app).post('/messages/file').set('Authorization', user.auth)
            .set('X-Upload-Size', '4').field('fileName', 'a.pdf').field('fileName', 'b.pdf')
            .attach('file', Buffer.from('test'), 'test.pdf');
        expect(result.status).toBe(400);
        expect(result.body.error).toBe('invalid_payload');
        await expect.poll(async () => (await sql`SELECT * FROM upload_reservations`.execute(db)).rows.length).toBe(0);
        expect(await storageUsage(user.id)).toBe(0);
    });
    it('does not let a delayed cleanup remove a fresh retry using the same upload ID', async () => {
        const user = await account(), id = randomUUID(), filename = `storage-test-${randomUUID()}.png`;
        const file = path.resolve('uploads', filename); createdFiles.push(file);
        await reserveUpload(user.id, 4, 200, 'image', id);
        await fs.writeFile(file, 'test'); await trackUpload(id, filename);
        let unblock!: () => void;
        const delayed = new Promise<void>(resolve => { unblock = resolve; });
        const unlink = vi.spyOn(fs, 'unlink').mockImplementationOnce(() => delayed);
        const first = releaseUpload(id);
        await expect.poll(() => unlink.mock.calls.length).toBe(1);
        await releaseUpload(id);
        expect(await reserveUpload(user.id, 4, 200, 'image', id)).toBe(id);
        unblock(); await first;
        expect((await sql`SELECT id FROM upload_reservations WHERE id=${id}`.execute(db)).rows).toHaveLength(1);
        await releaseUpload(id);
    });
    it('reserves capacity atomically and releases failed uploads', async () => {
        const user = await account();
        const ids = await Promise.all(Array.from({ length: 6 }, () => reserveUpload(user.id, 60, 200, 'image')));
        expect(ids.filter(Boolean)).toHaveLength(3);
        for (const id of ids) if (id) await releaseUpload(id);
        const next = await reserveUpload(user.id, 200, 200, 'image');
        expect(next).not.toBeNull();
        await releaseUpload(next!);
    });
    it('stores images for 3 days and retries without duplicates', async () => {
        const user = await account(), uploadID = randomUUID();
        const send = () => request(app).post('/messages/image').set('Authorization', user.auth)
            .set('X-Upload-ID', uploadID).set('X-Upload-Size', '4').attach('image', Buffer.from('test'), 'test.png');
        const first = await send(); remember(first.body);
        expect(first.status).toBe(201);
        expect(Date.parse(first.body.attachmentExpiresAt) - Date.parse(first.body.createdAt)).toBeGreaterThanOrEqual(3 * 86400000 - 1000);
        expect(await storageUsage(user.id)).toBe(4);
        const second = await send();
        expect(second.status).toBe(201);
        expect(second.body.id).toBe(first.body.id);
        expect(await storageUsage(user.id)).toBe(4);
        expect((await sql`SELECT * FROM upload_reservations`.execute(db)).rows).toHaveLength(0);
    });
    it('rejects falsified sizes while streaming and releases the reservation', async () => {
        const user = await account(true);
        const res = await request(app).post('/messages/file').set('Authorization', user.auth)
            .set('X-Upload-Size', '4').attach('file', Buffer.alloc(10000), 'test.pdf');
        expect(res.status).toBe(413);
        await expect.poll(async () => (await sql`SELECT * FROM upload_reservations`.execute(db)).rows.length).toBe(0);
        expect(await storageUsage(user.id)).toBe(0);
    });
    it('blocks expired downloads before cleanup and keeps the message after cleanup', async () => {
        const user = await account(true);
        const res = await request(app).post('/messages/file').set('Authorization', user.auth)
            .set('X-Upload-Size', '4').attach('file', Buffer.from('test'), 'test.pdf');
        remember(res.body);
        expect(res.status).toBe(201);
        expect(Date.parse(res.body.attachmentExpiresAt) - Date.parse(res.body.createdAt)).toBeGreaterThanOrEqual(7 * 86400000 - 1000);
        const url = `/api/media/${res.body.filePath}`;
        expect((await request(app).get(url).set('Authorization', user.auth)).status).toBe(200);
        await db.updateTable('messages').set({ attachment_expires_at: new Date(Date.now() - 1000).toISOString() }).where('id', '=', res.body.id).execute();
        expect((await request(app).get(url).set('Authorization', user.auth)).status).toBe(410);
        expect((await request(app).get(`/uploads/${res.body.filePath}`)).status).toBe(404);
        await cleanupExpiredAttachments(); await cleanupExpiredAttachments();
        await expect(fs.stat(path.resolve('files', res.body.filePath))).rejects.toMatchObject({ code: 'ENOENT' });
        const list = await request(app).get('/messages').set('Authorization', user.auth);
        expect(list.body.messages[0]).toMatchObject({ id: res.body.id, attachmentExpired: true, isDeleted: false });
        expect(list.body.messages[0].fileUrl).toBeUndefined();
        expect(await storageUsage(user.id)).toBe(0);
    });
    it('rejects limit plus one before reading the body', async () => {
        const user = await account(true);
        for (const [kind, limit] of [['image', IMAGE_LIMIT], ['file', FILE_LIMIT]] as const) {
            const res = await request(app).post(`/messages/${kind}`).set('Authorization', user.auth)
                .set('X-Upload-Size', String(limit + 1));
            expect(res.status).toBe(413);
        }
        expect((await sql`SELECT * FROM upload_reservations`.execute(db)).rows).toHaveLength(0);
    });
    it('recovers crashed uploads without removing successful attachments', async () => {
        const user = await account();
        const id = await reserveUpload(user.id, 4, 200, 'image');
        const filename = `storage-test-${randomUUID()}.png`;
        const file = path.resolve('uploads', filename); createdFiles.push(file);
        await fs.writeFile(file, 'test'); await trackUpload(id!, filename);
        await sql`UPDATE upload_reservations SET expires_at = '2000-01-01T00:00:00.000Z' WHERE id=${id}`.execute(db);
        await cleanupExpiredAttachments();
        await expect(fs.stat(file)).rejects.toMatchObject({ code: 'ENOENT' });
        expect((await sql`SELECT * FROM upload_reservations`.execute(db)).rows).toHaveLength(0);
    });
    it('accepts the 50 MB image boundary', async () => {
        const user = await account(), temp = path.join('/tmp', `synca-${randomUUID()}.png`);
        const handle = await fs.open(temp, 'w'); await handle.truncate(IMAGE_LIMIT); await handle.close();
        try {
            const res = await request(app).post('/messages/image').set('Authorization', user.auth)
                .set('X-Upload-Size', String(IMAGE_LIMIT)).attach('image', temp);
            remember(res.body); expect(res.status).toBe(201); expect(await storageUsage(user.id)).toBe(IMAGE_LIMIT);
        } finally { await fs.rm(temp, { force: true }); }
    }, 30000);
    it('accepts a 200 MB file streamed from disk', async () => {
        const user = await account(true), temp = path.join('/tmp', `synca-${randomUUID()}.pdf`);
        const handle = await fs.open(temp, 'w');
        await handle.truncate(FILE_LIMIT); await handle.close();
        try {
            const res = await request(app).post('/messages/file').set('Authorization', user.auth)
                .set('X-Upload-Size', String(FILE_LIMIT)).attach('file', temp);
            remember(res.body);
            expect(res.status).toBe(201);
            expect(res.body.fileSize).toBe(FILE_LIMIT);
        } finally { await fs.rm(temp, { force: true }); }
    }, 30000);
});
