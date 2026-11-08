import { describe, it, expect, beforeAll, beforeEach, vi } from 'vitest';
import request from 'supertest';
import app from '../src/app.js';
import { runMigrations } from '../src/migrate.js';
import { resetDb, createSession as dbCreateSession } from '../src/store.js';
import { db } from '../src/db.js';
import { v4 as uuidv4 } from 'uuid';
import fs from 'fs';
import path from 'path';

// Create a test user directly in DB (bypassing Apple auth for testing)
async function createTestUser(options?: {
    trialStartedAt?: string | null;
    trialEndsAt?: string | null;
    purchaseDate?: string | null;
    subscriptionExpiresAt?: string | null;
    lifetimePurchasedAt?: string | null;
    storeProductId?: string | null;
}) {
    const userId = uuidv4();
    const token = uuidv4();
    const now = new Date().toISOString();

    await db.insertInto('users').values({
        id: userId,
        apple_user_id: `test_apple_${userId}`,
        email: 'test@example.com',
        nickname: 'Test User',
        trial_started_at: options?.trialStartedAt ?? now,
        trial_ends_at: options?.trialEndsAt ?? new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        purchase_date: options?.purchaseDate ?? null,
        subscription_expires_at: options?.subscriptionExpiresAt ?? null,
        lifetime_purchased_at: options?.lifetimePurchasedAt ?? null,
        store_product_id: options?.storeProductId ?? null,
        created_at: now,
        updated_at: now,
    }).execute();

    await dbCreateSession(token, userId);

    return { userId, token, authHeader: `Bearer ${token}` };
}

describe('Synca API', () => {
    beforeAll(async () => {
        await runMigrations();
    });

    beforeEach(async () => {
        await resetDb();
    });

    describe('compatible category palette', () => {
        it('round trips presets and updates record metadata through sync, preserving name-only edits', async () => {
            const { authHeader } = await createTestUser();
            const made = await request(app).post('/message-categories').set('Authorization', authHeader)
                .send({ name: 'Palette', color: 'slate', colorHex: '#4169A8' });
            expect(made.status).toBe(201);
            expect(made.body).toMatchObject({ color: 'sky', colorHex: '#4169a8' });
            const record = await request(app).post('/messages').set('Authorization', authHeader)
                .send({ textContent: 'example', categoryId: made.body.id });
            expect(record.status).toBe(201);
            expect(record.body.categoryColorHex).toBe('#4169a8');
            const renamed = await request(app).patch(`/message-categories/${made.body.id}`).set('Authorization', authHeader).send({ name: 'Renamed' });
            expect(renamed.body.colorHex).toBe('#4169a8');
            expect(renamed.body.updatedAt > made.body.updatedAt).toBe(true);
            const synced = await request(app).get('/messages').query({ since: record.body.updatedAt }).set('Authorization', authHeader);
            expect(synced.body.messages).toEqual(expect.arrayContaining([expect.objectContaining({ id: record.body.id, categoryName: 'Renamed', categoryColorHex: '#4169a8' })]));
            const legacy = await request(app).patch(`/message-categories/${made.body.id}`).set('Authorization', authHeader).send({ color: 'mint' });
            expect(legacy.body.color).toBe('mint');
            expect(legacy.body.colorHex).toBeUndefined();
            const list = await request(app).get('/messages').set('Authorization', authHeader);
            expect(list.body.messages[0].categoryColor).toBe('mint');
            expect(list.body.messages[0].categoryColorHex).toBeUndefined();
        });
        it('serializes overlapping recolor and name-only patches without losing metadata or revisions', async () => {
            const { updateMessageCategory } = await import('../src/store.js');
            const { userId, authHeader } = await createTestUser();
            const made = await request(app).post('/message-categories').set('Authorization', authHeader)
                .send({ name: 'Original', color: 'slate', colorHex: '#676d78' });
            expect(made.status).toBe(201);
            const record = await request(app).post('/messages').set('Authorization', authHeader)
                .send({ textContent: 'Concurrent metadata', categoryId: made.body.id });
            // Start both mutations without awaiting: same clock and same SQLite connection.
            // The second write must read the first write's committed palette and revision.
            const [recolored, renamed] = await Promise.all([
                updateMessageCategory({ id: made.body.id, userId, colorHex: '#4169a8', now: made.body.updatedAt }),
                updateMessageCategory({ id: made.body.id, userId, name: 'Concurrent rename', now: made.body.updatedAt }),
            ]);
            expect(recolored).toMatchObject({ color: 'sky', colorHex: '#4169a8' });
            expect(renamed).toMatchObject({ name: 'Concurrent rename', color: 'sky', colorHex: '#4169a8' });
            expect(recolored!.updatedAt > made.body.updatedAt).toBe(true);
            expect(renamed!.updatedAt > recolored!.updatedAt).toBe(true);
            const categories = await request(app).get('/message-categories').set('Authorization', authHeader);
            expect(categories.body.categories.find((c: { id: string }) => c.id === made.body.id)).toMatchObject(renamed!);
            const messages = await request(app).get('/messages').set('Authorization', authHeader);
            const finalRecord = messages.body.messages.find((m: { id: string }) => m.id === record.body.id);
            expect(finalRecord).toMatchObject({ categoryName: 'Concurrent rename', categoryColor: 'sky', categoryColorHex: '#4169a8' });
            expect(finalRecord.updatedAt > record.body.updatedAt).toBe(true);
        });
        it('permits default colors but forbids rename/delete/order and isolates users', async () => {
            const { authHeader } = await createTestUser();
            const initial = await request(app).get('/message-categories').set('Authorization', authHeader);
            const defaultId = initial.body.categories[0].id;
            const color = await request(app).patch(`/message-categories/${defaultId}`).set('Authorization', authHeader).send({ colorHex: '#8da35e' });
            expect(color.status).toBe(200);
            expect(color.body).toMatchObject({ color: 'mint', colorHex: '#8da35e', isDefault: true });
            expect((await request(app).patch(`/message-categories/${defaultId}`).set('Authorization', authHeader).send({ name: 'Changed', color: 'sky' })).status).toBe(404);
            expect((await request(app).delete(`/message-categories/${defaultId}`).set('Authorization', authHeader)).status).toBe(404);
            expect((await request(app).put('/message-categories/order').set('Authorization', authHeader).send({ categoryIds: [defaultId] })).status).toBe(400);
            expect((await request(app).patch(`/message-categories/${defaultId}`).set('Authorization', authHeader).send({ color: 'sky', sortOrder: 1 })).status).toBe(400);
            const other = await createTestUser();
            expect((await request(app).patch(`/message-categories/${defaultId}`).set('Authorization', other.authHeader).send({ colorHex: '#8276c2' })).status).toBe(404);
            const listed = await request(app).get('/message-categories').set('Authorization', authHeader);
            expect(listed.body.categories[0]).toMatchObject({ id: defaultId, name: 'Default', colorHex: '#8da35e', sortOrder: 0 });
        });
        it('accepts precisely the shared 16 presets and rejects arbitrary or invalid legacy colors', async () => {
            const { categoryPalette } = await import('../src/categoryPalette.js');
            const { authHeader } = await createTestUser();
            expect(categoryPalette).toHaveLength(16);
            for (const preset of categoryPalette) {
                const result = await request(app).post('/message-categories').set('Authorization', authHeader)
                    .send({ name: preset.name, color: 'slate', colorHex: preset.hex });
                expect(result.status).toBe(201);
                expect(result.body).toMatchObject({ color: preset.color, colorHex: preset.hex });
            }
            for (const colorHex of ['#ffffff', '#4169a', 'red', 42]) {
                expect((await request(app).post('/message-categories').set('Authorization', authHeader).send({ name: 'Invalid', color: 'sky', colorHex })).status).toBe(400);
            }
            expect((await request(app).post('/message-categories').set('Authorization', authHeader).send({ name: 'Invalid', color: 'denim' })).status).toBe(400);
            const old = await request(app).post('/message-categories').set('Authorization', authHeader).send({ name: 'Old', color: 'rose' });
            expect(old.status).toBe(201);
            expect(old.body.colorHex).toBeUndefined();
            const cleared = await request(app).patch(`/message-categories/${old.body.id}`).set('Authorization', authHeader).send({ colorHex: null });
            expect(cleared.status).toBe(200);
            expect(cleared.body.colorHex).toBeUndefined();
        });
    });

    describe('record text character limits', () => {
        it.each(['a', '中', '😀', '👨‍👩‍👧‍👦', 'e\u0301'])('accepts 10000 and rejects 10001 graphemes for %s on create and edit', async character => {
            const { authHeader } = await createTestUser({ trialEndsAt: '2020-01-01T00:00:00.000Z' });
            const textContent = character.repeat(10000);
            const created = await request(app).post('/messages').set('Authorization', authHeader).send({ textContent });
            expect(created.status).toBe(201);
            expect(created.body.textContent).toBe(textContent);
            const tooLong = await request(app).post('/messages').set('Authorization', authHeader).send({ textContent: textContent + character });
            expect(tooLong.status).toBe(400);
            expect(tooLong.body.error).toBe('message_too_long');
            const edited = await request(app).patch(`/messages/${created.body.id}/text`).set('Authorization', authHeader)
                .send({ textContent, expectedUpdatedAt: created.body.updatedAt });
            expect(edited.status).toBe(200);
            expect(edited.body.textContent).toBe(textContent);
            const rejected = await request(app).patch(`/messages/${created.body.id}/text`).set('Authorization', authHeader)
                .send({ textContent: textContent + character, expectedUpdatedAt: edited.body.updatedAt });
            expect(rejected.status).toBe(400);
            expect(rejected.body.error).toBe('invalid_payload');
        });
        it('accepts escaped JSON for 10000 complex emoji', async () => {
            const { authHeader } = await createTestUser();
            const textContent = '👨‍👩‍👧‍👦'.repeat(10000);
            const escapedJson = JSON.stringify({ textContent }).replace(/[\u0080-\uffff]/g,
                character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));
            const response = await request(app).post('/messages').set('Authorization', authHeader)
                .set('Content-Type', 'application/json').send(escapedJson);
            expect(response.status).toBe(201);
            expect(response.body.textContent).toBe(textContent);
        });
        it('retains bounded request bodies and the smaller cap for unrelated APIs', async () => {
            const { authHeader } = await createTestUser();
            expect((await request(app).post('/messages').set('Authorization', authHeader).send({ textContent: 'x'.repeat(1024 * 1024) })).status).toBe(413);
            expect((await request(app).post('/unknown').send({ content: 'x'.repeat(110000) })).status).toBe(413);
        });
        it('keeps feedback at 2000 characters', async () => {
            const { authHeader } = await createTestUser();
            const response = await request(app).post('/feedback').set('Authorization', authHeader)
                .field('content', '中'.repeat(2001)).field('email', 'test@example.com');
            expect(response.status).toBe(400);
            expect(response.body.error).toBe('feedback_too_long');
        });
    });

    describe('PATCH /messages/:id/text', () => {
        const edit = (id: string, auth: string, textContent: string, expectedUpdatedAt: string) =>
            request(app).patch(`/messages/${id}/text`).set('Authorization', auth).send({ textContent, expectedUpdatedAt });

        it('updates pure text, preserves metadata, syncs and rejects stale edits', async () => {
            const { authHeader } = await createTestUser();
            const created = await request(app).post('/messages').set('Authorization', authHeader).send({ textContent: 'original' });
            expect(created.status).toBe(201);
            const completed = await request(app).patch(`/messages/${created.body.id}/completion`).set('Authorization', authHeader).send({ isCleared: true });
            const updated = await edit(created.body.id, authHeader, ' updated\ntext ', completed.body.updatedAt);
            expect(updated.status).toBe(200);
            expect(updated.body).toMatchObject({ textContent: ' updated\ntext ', isCleared: true, categoryId: created.body.categoryId, createdAt: created.body.createdAt });
            expect(updated.body.updatedAt > completed.body.updatedAt).toBe(true);
            const synced = await request(app).get('/messages').query({ since: completed.body.updatedAt }).set('Authorization', authHeader);
            expect(synced.body.messages).toContainEqual(expect.objectContaining({ id: created.body.id, textContent: ' updated\ntext ' }));
            const stale = await edit(created.body.id, authHeader, 'stale overwrite', completed.body.updatedAt);
            expect(stale.status).toBe(409);
            expect(stale.body.error).toBe('message_edit_conflict');
        });

        it('keeps edit revisions monotonic through category and legacy completion changes with a frozen clock', async () => {
            vi.useFakeTimers({ toFake: ['Date'] });
            vi.setSystemTime(new Date('2030-01-01T00:00:00.000Z'));
            try {
                const { authHeader } = await createTestUser();
                const created = await request(app).post('/messages').set('Authorization', authHeader).send({ textContent: 'original' });
                const { id, updatedAt } = created.body;
                const edited = await edit(id, authHeader, 'saved edit', updatedAt);
                expect(edited.status).toBe(200);
                const category = await request(app).post('/message-categories').set('Authorization', authHeader).send({ name: 'Work', color: 'sky' });
                expect(category.status).toBe(201);
                const moved = await request(app).patch(`/messages/${id}/category`).set('Authorization', authHeader).send({ categoryId: category.body.id });
                expect(moved.status).toBe(200);
                expect(moved.body.updatedAt > edited.body.updatedAt).toBe(true);
                expect((await edit(id, authHeader, 'stale overwrite', updatedAt)).status).toBe(409);
                await request(app).patch(`/messages/${id}/clear`).set('Authorization', authHeader);
                const cleared = await db.selectFrom('messages').selectAll().where('id', '=', id).executeTakeFirstOrThrow();
                expect(cleared.updated_at > moved.body.updatedAt).toBe(true);
                await request(app).delete(`/message-categories/${category.body.id}`).set('Authorization', authHeader);
                const recategorized = await db.selectFrom('messages').selectAll().where('id', '=', id).executeTakeFirstOrThrow();
                expect(recategorized.updated_at > cleared.updated_at).toBe(true);
                const restored = await request(app).patch(`/messages/${id}/completion`).set('Authorization', authHeader).send({ isCleared: false });
                await request(app).post('/messages/clear-all').set('Authorization', authHeader);
                const bulkCleared = await db.selectFrom('messages').selectAll().where('id', '=', id).executeTakeFirstOrThrow();
                expect(bulkCleared.updated_at > restored.body.updatedAt).toBe(true);
            } finally { vi.useRealTimers(); }
        });

        it('accepts only one of two competing drafts with the same timestamp', async () => {
            const { authHeader } = await createTestUser();
            const created = await request(app).post('/messages').set('Authorization', authHeader).send({ textContent: 'original' });
            const { id, updatedAt } = created.body;
            const results = await Promise.all([edit(id, authHeader, 'first', updatedAt), edit(id, authHeader, 'second', updatedAt)]);
            expect(results.map(result => result.status).sort()).toEqual([200, 409]);
            const winner = results.find(result => result.status === 200)!;
            const stored = await db.selectFrom('messages').selectAll().where('id', '=', id).executeTakeFirstOrThrow();
            expect(stored.text_content).toBe(winner.body.textContent);
        });

        it('requires auth, ownership, live records and a pure text type', async () => {
            const { authHeader } = await createTestUser();
            const other = await createTestUser();
            const created = await request(app).post('/messages').set('Authorization', authHeader).send({ textContent: 'private' });
            const { id, updatedAt } = created.body;
            expect((await request(app).patch(`/messages/${id}/text`).send({ textContent: 'bad', expectedUpdatedAt: updatedAt })).status).toBe(401);
            expect((await edit(id, other.authHeader, 'bad', updatedAt)).status).toBe(404);
            for (const type of ['image', 'file'] as const) {
                await db.updateTable('messages').set({ type }).where('id', '=', id).execute();
                expect((await edit(id, authHeader, 'bad', updatedAt)).status).toBe(422);
            }
            await db.updateTable('messages').set({ type: 'text', image_path: 'legacy.png' }).where('id', '=', id).execute();
            expect((await edit(id, authHeader, 'bad', updatedAt)).status).toBe(422);
            await db.updateTable('messages').set({ image_path: null, is_deleted: 1 }).where('id', '=', id).execute();
            expect((await edit(id, authHeader, 'bad', updatedAt)).status).toBe(404);
        });

        it('rejects empty, oversized, malformed and extra fields; accepts the exact UTF-16 limit', async () => {
            const { authHeader } = await createTestUser();
            const created = await request(app).post('/messages').set('Authorization', authHeader).send({ textContent: 'original' });
            const { id, updatedAt } = created.body;
            for (const text of ['', ' \n\t ', 'x'.repeat(10001), '😀'.repeat(10001)]) {
                expect((await edit(id, authHeader, text, updatedAt)).status).toBe(400);
            }
            expect((await edit(id, authHeader, 'ok', 'invalid')).status).toBe(400);
            expect((await request(app).patch(`/messages/${id}/text`).set('Authorization', authHeader).send({ textContent: 'ok', expectedUpdatedAt: updatedAt, categoryId: null })).status).toBe(400);
            expect((await edit(id, authHeader, '😀'.repeat(1000), updatedAt)).status).toBe(200);
        });
    });

    describe('GET /health', () => {
        it('should return ok', async () => {
            const res = await request(app).get('/health');
            expect(res.status).toBe(200);
            expect(res.body.ok).toBe(true);
            expect(res.body.service).toBe('synca');
        });
    });

    describe('Public pages', () => {
        it('should serve the English privacy policy page', async () => {
            const res = await request(app).get('/en/privacy-policy');

            expect(res.status).toBe(200);
            expect(res.headers['content-type']).toContain('text/html');
            expect(res.text).toContain('Synca Privacy Policy');
            expect(res.text).toContain('jieyu.li@icloud.com');
        });

        it('should serve the Chinese support page', async () => {
            const res = await request(app).get('/zh-hans/support');

            expect(res.status).toBe(200);
            expect(res.headers['content-type']).toContain('text/html');
            expect(res.text).toContain('Synca 支持页面');
            expect(res.text).toContain('免费版用户每日最多可新增 20 条内容');
        });
    });

    describe('Authentication', () => {
        it('should reject unauthenticated requests', async () => {
            const res = await request(app).get('/messages');
            expect(res.status).toBe(401);
        });

        it('should reject invalid token', async () => {
            const res = await request(app)
                .get('/messages')
                .set('Authorization', 'Bearer invalid-token');
            expect(res.status).toBe(401);
        });

        it('should delete account and associated data', async () => {
            const { userId, authHeader, token } = await createTestUser();
            const now = new Date().toISOString();
            const uploadsDir = path.resolve(process.cwd(), 'uploads');
            const filesDir = path.resolve(process.cwd(), 'files');
            const feedbackUploadsDir = path.resolve(process.cwd(), 'feedback_uploads');

            fs.mkdirSync(uploadsDir, { recursive: true });
            fs.mkdirSync(filesDir, { recursive: true });
            fs.mkdirSync(feedbackUploadsDir, { recursive: true });

            const imageFileName = `test-image-${uuidv4()}.png`;
            const docFileName = `test-doc-${uuidv4()}.pdf`;
            const feedbackFileName = `feedback-${uuidv4()}.png`;

            fs.writeFileSync(path.join(uploadsDir, imageFileName), 'img');
            fs.writeFileSync(path.join(filesDir, docFileName), 'doc');
            fs.writeFileSync(path.join(feedbackUploadsDir, feedbackFileName), 'feedback');

            await db.insertInto('message_categories').values({
                id: uuidv4(),
                user_id: userId,
                name: 'Default',
                color: 'slate',
                is_default: 1,
                created_at: now,
                updated_at: now,
            }).execute();

            await db.insertInto('messages').values([
                {
                    id: uuidv4(),
                    user_id: userId,
                    type: 'image',
                    text_content: null,
                    image_path: imageFileName,
                    file_path: null,
                    file_name: null,
                    file_size: null,
                    file_mime_type: null,
                    category_id: null,
                    is_cleared: 0,
                    is_deleted: 0,
                    source_device: 'Test',
                    created_at: now,
                    updated_at: now,
                },
                {
                    id: uuidv4(),
                    user_id: userId,
                    type: 'file',
                    text_content: null,
                    image_path: null,
                    file_path: docFileName,
                    file_name: 'doc.pdf',
                    file_size: 3,
                    file_mime_type: 'application/pdf',
                    category_id: null,
                    is_cleared: 0,
                    is_deleted: 0,
                    source_device: 'Test',
                    created_at: now,
                    updated_at: now,
                },
            ]).execute();

            await db.insertInto('feedbacks').values({
                id: uuidv4(),
                user_id: userId,
                content: 'help',
                email: 'test@example.com',
                image_paths: JSON.stringify([feedbackFileName]),
                device_model: 'Mac',
                os_version: '14.0',
                app_version: '1.0',
                created_at: now,
                updated_at: now,
            }).execute();

            await db.insertInto('device_push_tokens').values({
                id: uuidv4(),
                user_id: userId,
                platform: 'ios',
                token: `push-${uuidv4()}`,
                apns_environment: 'sandbox',
                topic: null,
                is_active: 1,
                last_error: null,
                last_sent_at: null,
                created_at: now,
                updated_at: now,
            }).execute();

            await db.insertInto('iap_transactions').values({
                transaction_id: `tx-${uuidv4()}`,
                original_transaction_id: null,
                user_id: userId,
                product_id: 'org.haerth.synca.unlimited.monthly',
                environment: 'Sandbox',
                type: 'Auto-Renewable Subscription',
                app_account_token: null,
                purchase_date: now,
                original_purchase_date: now,
                expires_at: null,
                revocation_date: null,
                is_upgraded: 0,
                signed_transaction_info: 'signed',
                created_at: now,
                updated_at: now,
            }).execute();

            const res = await request(app)
                .delete('/me/account')
                .set('Authorization', authHeader);

            expect(res.status).toBe(200);
            expect(res.body.ok).toBe(true);

            const user = await db.selectFrom('users').select('id').where('id', '=', userId).executeTakeFirst();
            const messages = await db.selectFrom('messages').select('id').where('user_id', '=', userId).execute();
            const categories = await db.selectFrom('message_categories').select('id').where('user_id', '=', userId).execute();
            const feedbacks = await db.selectFrom('feedbacks').select('id').where('user_id', '=', userId).execute();
            const sessions = await db.selectFrom('sessions').select('token').where('token', '=', token).execute();
            const pushTokens = await db.selectFrom('device_push_tokens').select('id').where('user_id', '=', userId).execute();
            const transactions = await db.selectFrom('iap_transactions').select('transaction_id').where('user_id', '=', userId).execute();

            expect(user).toBeUndefined();
            expect(messages).toHaveLength(0);
            expect(categories).toHaveLength(0);
            expect(feedbacks).toHaveLength(0);
            expect(sessions).toHaveLength(0);
            expect(pushTokens).toHaveLength(0);
            expect(transactions).toHaveLength(0);
            expect(fs.existsSync(path.join(uploadsDir, imageFileName))).toBe(false);
            expect(fs.existsSync(path.join(filesDir, docFileName))).toBe(false);
            expect(fs.existsSync(path.join(feedbackUploadsDir, feedbackFileName))).toBe(false);
        });
    });

    describe('Messages API', () => {
        it('should create and list text messages', async () => {
            const { authHeader } = await createTestUser();

            // Create a text message
            const createRes = await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '明天开会', sourceDevice: 'iPhone' });

            expect(createRes.status).toBe(201);
            expect(createRes.body.type).toBe('text');
            expect(createRes.body.textContent).toBe('明天开会');
            expect(createRes.body.sourceDevice).toBe('iPhone');
            expect(createRes.body.isCleared).toBe(false);

            // List messages
            const listRes = await request(app)
                .get('/messages')
                .set('Authorization', authHeader);

            expect(listRes.status).toBe(200);
            expect(listRes.body.messages).toHaveLength(1);
            expect(listRes.body.messages[0].textContent).toBe('明天开会');
        });

        it('should support since filter for sync', async () => {
            const { authHeader } = await createTestUser();

            // Create a message
            const res1 = await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '第一条' });

            const firstMessageTime = res1.body.updatedAt;

            // Wait a tiny bit
            await new Promise((r) => setTimeout(r, 10));

            // Create another message
            await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '第二条' });

            // Sync with since filter
            const syncRes = await request(app)
                .get(`/messages?since=${firstMessageTime}`)
                .set('Authorization', authHeader);

            expect(syncRes.status).toBe(200);
            expect(syncRes.body.messages).toHaveLength(1);
            expect(syncRes.body.messages[0].textContent).toBe('第二条');
        });

        it('should clear a single message', async () => {
            const { authHeader } = await createTestUser();

            const createRes = await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '待清理' });

            const messageId = createRes.body.id;

            const clearRes = await request(app)
                .patch(`/messages/${messageId}/clear`)
                .set('Authorization', authHeader);

            expect(clearRes.status).toBe(200);
            expect(clearRes.body.ok).toBe(true);

            // Verify it's cleared
            const listRes = await request(app)
                .get('/messages')
                .set('Authorization', authHeader);

            expect(listRes.body.messages[0].isCleared).toBe(true);
        });

        it('sets completion explicitly, retries safely and refuses foreign or deleted records', async () => {
            const { authHeader } = await createTestUser();
            const other = await createTestUser();
            const made = await request(app).post('/messages').set('Authorization', authHeader).send({ textContent: 'reversible' });
            const endpoint = `/messages/${made.body.id}/completion`;
            const set = (isCleared: unknown, auth = authHeader) => request(app).patch(endpoint).set('Authorization', auth).send({ isCleared });
            expect((await set(true)).body.isCleared).toBe(true);
            const restored = await set(false);
            expect(restored.status).toBe(200);
            expect(restored.body.isCleared).toBe(false);
            expect((await set(false)).body.updatedAt).toBe(restored.body.updatedAt);
            expect((await set(true, other.authHeader)).status).toBe(404);
            expect((await set('false')).status).toBe(400);
            const list = await request(app).get('/messages').set('Authorization', authHeader);
            expect(list.body.messages[0].isCleared).toBe(false);
            await request(app).delete(`/messages/${made.body.id}`).set('Authorization', authHeader);
            expect((await set(false)).status).toBe(404);
        });

        it('should clear all messages', async () => {
            const { authHeader } = await createTestUser();

            await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '消息1' });

            await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '消息2' });

            const clearRes = await request(app)
                .post('/messages/clear-all')
                .set('Authorization', authHeader);

            expect(clearRes.status).toBe(200);
            expect(clearRes.body.clearedCount).toBe(2);

            // Verify uncleared count is 0
            const countRes = await request(app)
                .get('/messages/uncleared-count')
                .set('Authorization', authHeader);

            expect(countRes.body.count).toBe(0);
        });

        it('should return correct uncleared count', async () => {
            const { authHeader } = await createTestUser();

            // Create 3 messages
            for (let i = 0; i < 3; i++) {
                await request(app)
                    .post('/messages')
                    .set('Authorization', authHeader)
                    .send({ textContent: `消息${i}` });
            }

            let countRes = await request(app)
                .get('/messages/uncleared-count')
                .set('Authorization', authHeader);
            expect(countRes.body.count).toBe(3);

            // Clear one
            const listRes = await request(app)
                .get('/messages')
                .set('Authorization', authHeader);
            await request(app)
                .patch(`/messages/${listRes.body.messages[0].id}/clear`)
                .set('Authorization', authHeader);

            countRes = await request(app)
                .get('/messages/uncleared-count')
                .set('Authorization', authHeader);
            expect(countRes.body.count).toBe(2);
        });

        it('should reject empty text', async () => {
            const { authHeader } = await createTestUser();

            const res = await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '' });

            expect(res.status).toBe(400);
        });

        it('should return free access status for new users', async () => {
            const { authHeader } = await createTestUser();

            const res = await request(app)
                .get('/me/access-status')
                .set('Authorization', authHeader);

            expect(res.status).toBe(200);
            expect(res.body.accessStatus.plan).toBe('free');
            expect(res.body.accessStatus.isTrial).toBe(false);
            expect(res.body.accessStatus.todayLimit).toBe(20);
        });

        it('should enforce the daily free limit', async () => {
            const { authHeader } = await createTestUser();

            for (let i = 0; i < 20; i += 1) {
                const createRes = await request(app)
                    .post('/messages')
                    .set('Authorization', authHeader)
                    .send({ textContent: `消息${i}` });
                expect(createRes.status).toBe(201);
            }

            const blockedRes = await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '第 21 条' });

            expect(blockedRes.status).toBe(403);
            expect(blockedRes.body.error).toBe('daily_limit_reached');
            expect(blockedRes.body.accessStatus.plan).toBe('free');
            expect(blockedRes.body.accessStatus.todayUsed).toBe(20);
            expect(blockedRes.body.accessStatus.todayLimit).toBe(20);
        });

        it('should not restore free quota after completed messages are cleared and deleted', async () => {
            const { authHeader } = await createTestUser();

            for (let i = 0; i < 20; i += 1) {
                const createRes = await request(app)
                    .post('/messages')
                    .set('Authorization', authHeader)
                    .send({ textContent: `消息${i}` });
                expect(createRes.status).toBe(201);
            }

            const clearRes = await request(app)
                .post('/messages/clear-all')
                .set('Authorization', authHeader);
            expect(clearRes.status).toBe(200);
            expect(clearRes.body.clearedCount).toBe(20);

            const deleteCompletedRes = await request(app)
                .post('/messages/delete-completed')
                .set('Authorization', authHeader);
            expect(deleteCompletedRes.status).toBe(200);
            expect(deleteCompletedRes.body.deletedCount).toBe(20);

            const accessStatusRes = await request(app)
                .get('/me/access-status')
                .set('Authorization', authHeader);
            expect(accessStatusRes.status).toBe(200);
            expect(accessStatusRes.body.accessStatus.plan).toBe('free');
            expect(accessStatusRes.body.accessStatus.todayUsed).toBe(20);
            expect(accessStatusRes.body.accessStatus.todayLimit).toBe(20);

            const blockedRes = await request(app)
                .post('/messages')
                .set('Authorization', authHeader)
                .send({ textContent: '删完后再发一条' });

            expect(blockedRes.status).toBe(403);
            expect(blockedRes.body.error).toBe('daily_limit_reached');
            expect(blockedRes.body.accessStatus.todayUsed).toBe(20);
        });
    });

    describe('Push Token API', () => {
        it('should register a push token', async () => {
            const { authHeader } = await createTestUser();

            const fakeToken = 'a'.repeat(64);
            const res = await request(app)
                .post('/me/push-token')
                .set('Authorization', authHeader)
                .send({
                    token: fakeToken,
                    platform: 'ios',
                    apnsEnvironment: 'sandbox',
                });

            expect(res.status).toBe(200);
            expect(res.body.ok).toBe(true);
        });

        it('should reject invalid push token', async () => {
            const { authHeader } = await createTestUser();

            const res = await request(app)
                .post('/me/push-token')
                .set('Authorization', authHeader)
                .send({ token: 'too-short' });

            expect(res.status).toBe(400);
        });
    });

    describe('Image Upload', () => {
        it('should upload an image message', async () => {
            const { authHeader } = await createTestUser();

            // Create a minimal valid PNG buffer (1x1 pixel)
            const pngHeader = Buffer.from([
                0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            ]);

            const res = await request(app)
                .post('/messages/image')
                .set('Authorization', authHeader)
                .attach('image', pngHeader, { filename: 'test.png', contentType: 'image/png' })
                .field('sourceDevice', 'iPhone');

            expect(res.status).toBe(201);
            expect(res.body.type).toBe('image');
            expect(res.body.imageUrl).toBeTruthy();
        });
    });

    describe('Data Isolation', () => {
        it('should not show messages from other users', async () => {
            const user1 = await createTestUser();
            const user2 = await createTestUser();

            await request(app)
                .post('/messages')
                .set('Authorization', user1.authHeader)
                .send({ textContent: 'User 1 只有他能看到' });

            const res = await request(app)
                .get('/messages')
                .set('Authorization', user2.authHeader);

            expect(res.body.messages).toHaveLength(0);
        });

        it('should not allow clearing other user messages', async () => {
            const user1 = await createTestUser();
            const user2 = await createTestUser();

            const createRes = await request(app)
                .post('/messages')
                .set('Authorization', user1.authHeader)
                .send({ textContent: 'User 1 的消息' });

            const res = await request(app)
                .patch(`/messages/${createRes.body.id}/clear`)
                .set('Authorization', user2.authHeader);

            expect(res.status).toBe(404);
        });
    });

    describe('Feedback API', () => {
        it('should submit feedback with email and optional images', async () => {
            const { authHeader } = await createTestUser();

            const res = await request(app)
                .post('/feedback')
                .set('Authorization', authHeader)
                .field('content', 'The composer feels great overall, but I found a sync issue.')
                .field('email', 'tester@example.com')
                .attach('images', Buffer.from('fake-image'), {
                    filename: 'feedback.png',
                    contentType: 'image/png',
                });

            expect(res.status).toBe(201);
            expect(res.body.ok).toBe(true);
        });

        it('should reject feedback without required fields', async () => {
            const { authHeader } = await createTestUser();

            const res = await request(app)
                .post('/feedback')
                .set('Authorization', authHeader)
                .field('content', '')
                .field('email', '');

            expect(res.status).toBe(400);
        });
    });
});
