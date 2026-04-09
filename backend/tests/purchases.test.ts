import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../src/db.js';
import { runMigrations } from '../src/migrate.js';
import { createSession as dbCreateSession, resetDb } from '../src/store.js';

const verifySignedTransactionInfoMock = vi.fn();
const signedJws = (suffix: string) => `signed-transaction-jws-${suffix}-payload`;

vi.mock('../src/iap.js', async () => {
    const actual = await vi.importActual<typeof import('../src/iap.js')>('../src/iap.js');
    return {
        ...actual,
        verifySignedTransactionInfo: verifySignedTransactionInfoMock,
    };
});

const { default: app } = await import('../src/app.js');

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
        apple_user_id: `purchase_test_${userId}`,
        email: 'purchase@example.com',
        nickname: 'Purchase Test User',
        trial_started_at: options?.trialStartedAt ?? now,
        trial_ends_at: options?.trialEndsAt ?? new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
        purchase_date: options?.purchaseDate ?? null,
        subscription_expires_at: options?.subscriptionExpiresAt ?? null,
        lifetime_purchased_at: options?.lifetimePurchasedAt ?? null,
        store_product_id: options?.storeProductId ?? null,
        created_at: now,
        updated_at: now,
    }).execute();

    await dbCreateSession(token, userId);

    return { userId, authHeader: `Bearer ${token}` };
}

describe('Purchase Sync API', () => {
    beforeAll(async () => {
        await runMigrations();
    });

    beforeEach(async () => {
        verifySignedTransactionInfoMock.mockReset();
        await resetDb();
    });

    it('should unlock Unlimited monthly after syncing a verified subscription purchase', async () => {
        const { userId, authHeader } = await createTestUser();
        const now = Date.now();
        const expiresAt = now + 30 * 24 * 60 * 60 * 1000;

        verifySignedTransactionInfoMock.mockResolvedValue({
            transactionId: '200000000000000',
            originalTransactionId: '200000000000000',
            productId: 'org.haerth.synca.unlimited.monthly',
            appAccountToken: userId,
            environment: 'Sandbox',
            purchaseDate: now,
            originalPurchaseDate: now,
            expiresDate: expiresAt,
            revocationDate: undefined,
            isUpgraded: false,
            type: 'Auto-Renewable Subscription',
        });

        const res = await request(app)
            .post('/me/purchases/sync')
            .set('Authorization', authHeader)
            .send({ signedTransactions: [signedJws('monthly')] });

        expect(res.status).toBe(200);
        expect(res.body.accessStatus.plan).toBe('unlimited');
        expect(res.body.accessStatus.isUnlimited).toBe(true);
        expect(res.body.accessStatus.unlimitedSource).toBe('subscription');
        expect(res.body.accessStatus.storeProductId).toBe('org.haerth.synca.unlimited.monthly');
        expect(res.body.accessStatus.subscriptionExpiresAt).toBeTruthy();
    });

    it('should unlock Unlimited yearly after syncing a verified subscription purchase', async () => {
        const { userId, authHeader } = await createTestUser();
        const now = Date.now();
        const expiresAt = now + 365 * 24 * 60 * 60 * 1000;

        verifySignedTransactionInfoMock.mockResolvedValue({
            transactionId: '200000000000001',
            originalTransactionId: '200000000000001',
            productId: 'org.haerth.synca.unlimited.yearly',
            appAccountToken: userId,
            environment: 'Sandbox',
            purchaseDate: now,
            originalPurchaseDate: now,
            expiresDate: expiresAt,
            revocationDate: undefined,
            isUpgraded: false,
            type: 'Auto-Renewable Subscription',
        });

        const res = await request(app)
            .post('/me/purchases/sync')
            .set('Authorization', authHeader)
            .send({ signedTransactions: [signedJws('yearly')] });

        expect(res.status).toBe(200);
        expect(res.body.accessStatus.plan).toBe('unlimited');
        expect(res.body.accessStatus.isUnlimited).toBe(true);
        expect(res.body.accessStatus.unlimitedSource).toBe('subscription');
        expect(res.body.accessStatus.storeProductId).toBe('org.haerth.synca.unlimited.yearly');
        expect(res.body.accessStatus.subscriptionExpiresAt).toBeTruthy();
    });

    it('should unlock Lifetime when syncing a verified lifetime purchase', async () => {
        const { userId, authHeader } = await createTestUser();
        const now = Date.now();

        verifySignedTransactionInfoMock.mockResolvedValue({
            transactionId: '200000000000002',
            originalTransactionId: '200000000000002',
            productId: 'org.haerth.synca.unlimited.lifetime',
            appAccountToken: userId,
            environment: 'Sandbox',
            purchaseDate: now,
            originalPurchaseDate: now,
            revocationDate: undefined,
            isUpgraded: false,
            type: 'Non-Consumable',
        });

        const res = await request(app)
            .post('/me/purchases/sync')
            .set('Authorization', authHeader)
            .send({ signedTransactions: [signedJws('lifetime')] });

        expect(res.status).toBe(200);
        expect(res.body.accessStatus.plan).toBe('unlimited');
        expect(res.body.accessStatus.unlimitedSource).toBe('lifetime');
        expect(res.body.accessStatus.storeProductId).toBe('org.haerth.synca.unlimited.lifetime');
        expect(res.body.accessStatus.purchaseDate).toBeTruthy();
        expect(res.body.accessStatus.subscriptionExpiresAt).toBeNull();
    });

    it('should reject purchase sync when the app account token belongs to another user', async () => {
        const { authHeader } = await createTestUser();

        verifySignedTransactionInfoMock.mockResolvedValue({
            transactionId: '200000000000003',
            originalTransactionId: '200000000000003',
            productId: 'org.haerth.synca.unlimited.monthly',
            appAccountToken: uuidv4(),
            environment: 'Sandbox',
            purchaseDate: Date.now(),
            expiresDate: Date.now() + 10_000,
            revocationDate: undefined,
            isUpgraded: false,
            type: 'Auto-Renewable Subscription',
        });

        const res = await request(app)
            .post('/me/purchases/sync')
            .set('Authorization', authHeader)
            .send({ signedTransactions: [signedJws('mismatch')] });

        expect(res.status).toBe(403);
        expect(res.body.error).toBe('purchase_account_mismatch');
    });

    it('should ignore unsupported products and keep the user on Free after trial ends', async () => {
        const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
        const { userId, authHeader } = await createTestUser({
            trialStartedAt: yesterday,
            trialEndsAt: yesterday,
        });

        verifySignedTransactionInfoMock.mockResolvedValue({
            transactionId: '200000000000004',
            originalTransactionId: '200000000000004',
            productId: 'com.example.unsupported',
            appAccountToken: userId,
            environment: 'Sandbox',
            purchaseDate: Date.now(),
            revocationDate: undefined,
            isUpgraded: false,
            type: 'Non-Consumable',
        });

        const res = await request(app)
            .post('/me/purchases/sync')
            .set('Authorization', authHeader)
            .send({ signedTransactions: [signedJws('unsupported')] });

        expect(res.status).toBe(200);
        expect(res.body.accessStatus.plan).toBe('free');
        expect(res.body.accessStatus.isUnlimited).toBe(false);
        expect(res.body.accessStatus.todayLimit).toBe(20);
    });

    it('should include a lifetime upgrade offer for an active monthly subscriber when codes are available', async () => {
        const now = new Date().toISOString();
        const { userId, authHeader } = await createTestUser({
            purchaseDate: now,
            subscriptionExpiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
            storeProductId: 'org.haerth.synca.unlimited.monthly',
        });

        await db.insertInto('lifetime_upgrade_offer_codes').values({
            id: uuidv4(),
            offer_kind: 'monthly_to_lifetime',
            code: 'MONTHLYUPGRADE001',
            assigned_user_id: null,
            assigned_at: null,
            redeemed_at: null,
            is_active: 1,
            created_at: now,
            updated_at: now,
        }).execute();

        const res = await request(app)
            .get('/me/access-status')
            .set('Authorization', authHeader);

        expect(res.status).toBe(200);
        expect(res.body.accessStatus.lifetimeUpgradeOffer).toMatchObject({
            kind: 'monthly_to_lifetime',
            discountedPriceLabel: '¥78',
            isCodeAvailable: true,
        });
        expect(res.body.accessStatus.lifetimeUpgradeOffer.code).toBe('MONTHLYUPGRADE001');
    });

    it('should assign a one-time lifetime upgrade code to an eligible subscriber', async () => {
        const now = new Date().toISOString();
        const { authHeader } = await createTestUser({
            purchaseDate: now,
            subscriptionExpiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
            storeProductId: 'org.haerth.synca.unlimited.yearly',
        });

        await db.insertInto('lifetime_upgrade_offer_codes').values({
            id: uuidv4(),
            offer_kind: 'yearly_to_lifetime',
            code: 'YEARLYUPGRADE001',
            assigned_user_id: null,
            assigned_at: null,
            redeemed_at: null,
            is_active: 1,
            created_at: now,
            updated_at: now,
        }).execute();

        const res = await request(app)
            .post('/me/lifetime-upgrade-offer-code')
            .set('Authorization', authHeader)
            .send({ kind: 'yearly_to_lifetime' });

        expect(res.status).toBe(200);
        expect(res.body.code).toBe('YEARLYUPGRADE001');
        expect(res.body.discountedPriceLabel).toBe('¥58');
    });
});
