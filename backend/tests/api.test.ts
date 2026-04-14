import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import request from 'supertest';
import app from '../src/app.js';
import { runMigrations } from '../src/migrate.js';
import { resetDb, createSession as dbCreateSession } from '../src/store.js';
import { db } from '../src/db.js';
import { v4 as uuidv4 } from 'uuid';

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
