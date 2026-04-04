import { db } from './db.js';
import { v4 as uuidv4 } from 'uuid';
import { SyncaUser, SyncaMessage } from './types.js';
import { UsersTable, MessagesTable, IapTransactionsTable } from './db_types.js';

// ── Mappers ──

function toUser(row: UsersTable): SyncaUser {
    return {
        id: row.id,
        appleUserId: row.apple_user_id,
        email: row.email ?? undefined,
        nickname: row.nickname,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    };
}

function toMessage(row: MessagesTable, baseUrl?: string): SyncaMessage {
    return {
        id: row.id,
        userId: row.user_id,
        type: row.type as 'text' | 'image',
        textContent: row.text_content ?? undefined,
        imagePath: row.image_path ?? undefined,
        imageUrl: row.image_path && baseUrl ? `${baseUrl}/uploads/${row.image_path}` : undefined,
        isCleared: row.is_cleared === 1,
        isDeleted: row.is_deleted === 1,
        sourceDevice: row.source_device ?? undefined,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    };
}

// ── User DAO ──

export async function getUserByAppleId(appleUserId: string): Promise<SyncaUser | undefined> {
    const row = await db.selectFrom('users')
        .selectAll()
        .where('apple_user_id', '=', appleUserId)
        .executeTakeFirst();
    return row ? toUser(row) : undefined;
}

export async function getUser(id: string): Promise<SyncaUser | undefined> {
    const row = await db.selectFrom('users')
        .selectAll()
        .where('id', '=', id)
        .executeTakeFirst();
    return row ? toUser(row) : undefined;
}

export async function createUser(user: {
    id: string;
    appleUserId: string;
    email?: string | null;
    nickname: string;
    now: string;
    trialStartedAt?: string | null;
    trialEndsAt?: string | null;
}): Promise<SyncaUser> {
    await db.insertInto('users').values({
        id: user.id,
        apple_user_id: user.appleUserId,
        email: user.email ?? null,
        nickname: user.nickname,
        trial_started_at: user.trialStartedAt ?? null,
        trial_ends_at: user.trialEndsAt ?? null,
        purchase_date: null,
        subscription_expires_at: null,
        lifetime_purchased_at: null,
        store_product_id: null,
        created_at: user.now,
        updated_at: user.now,
    }).execute();
    return (await getUser(user.id))!;
}

export async function getUserAccessFields(userId: string): Promise<Pick<UsersTable, 'id' | 'trial_started_at' | 'trial_ends_at' | 'purchase_date' | 'subscription_expires_at' | 'lifetime_purchased_at' | 'store_product_id'> | undefined> {
    return db.selectFrom('users')
        .select([
            'id',
            'trial_started_at',
            'trial_ends_at',
            'purchase_date',
            'subscription_expires_at',
            'lifetime_purchased_at',
            'store_product_id',
        ])
        .where('id', '=', userId)
        .executeTakeFirst();
}

export async function upsertIapTransaction(input: {
    transactionId: string;
    originalTransactionId?: string | null;
    userId: string;
    productId: string;
    environment: string;
    type?: string | null;
    appAccountToken?: string | null;
    purchaseDate?: string | null;
    originalPurchaseDate?: string | null;
    expiresAt?: string | null;
    revocationDate?: string | null;
    isUpgraded: boolean;
    signedTransactionInfo: string;
    now: string;
}): Promise<void> {
    await db.insertInto('iap_transactions')
        .values({
            transaction_id: input.transactionId,
            original_transaction_id: input.originalTransactionId ?? null,
            user_id: input.userId,
            product_id: input.productId,
            environment: input.environment,
            type: input.type ?? null,
            app_account_token: input.appAccountToken ?? null,
            purchase_date: input.purchaseDate ?? null,
            original_purchase_date: input.originalPurchaseDate ?? null,
            expires_at: input.expiresAt ?? null,
            revocation_date: input.revocationDate ?? null,
            is_upgraded: input.isUpgraded ? 1 : 0,
            signed_transaction_info: input.signedTransactionInfo,
            created_at: input.now,
            updated_at: input.now,
        })
        .onConflict((oc) => oc.column('transaction_id').doUpdateSet({
            original_transaction_id: input.originalTransactionId ?? null,
            user_id: input.userId,
            product_id: input.productId,
            environment: input.environment,
            type: input.type ?? null,
            app_account_token: input.appAccountToken ?? null,
            purchase_date: input.purchaseDate ?? null,
            original_purchase_date: input.originalPurchaseDate ?? null,
            expires_at: input.expiresAt ?? null,
            revocation_date: input.revocationDate ?? null,
            is_upgraded: input.isUpgraded ? 1 : 0,
            signed_transaction_info: input.signedTransactionInfo,
            updated_at: input.now,
        }))
        .execute();
}

export async function listUserIapTransactions(userId: string): Promise<IapTransactionsTable[]> {
    return db.selectFrom('iap_transactions')
        .selectAll()
        .where('user_id', '=', userId)
        .orderBy('purchase_date', 'asc')
        .execute();
}

export async function updateUserPurchaseAccess(input: {
    userId: string;
    purchaseDate?: string | null;
    subscriptionExpiresAt?: string | null;
    lifetimePurchasedAt?: string | null;
    storeProductId?: string | null;
    now: string;
}): Promise<void> {
    await db.updateTable('users')
        .set({
            purchase_date: input.purchaseDate ?? null,
            subscription_expires_at: input.subscriptionExpiresAt ?? null,
            lifetime_purchased_at: input.lifetimePurchasedAt ?? null,
            store_product_id: input.storeProductId ?? null,
            updated_at: input.now,
        })
        .where('id', '=', input.userId)
        .execute();
}

// ── Message DAO ──

export async function listMessages(params: {
    userId: string;
    since?: string;
    limit?: number;
    baseUrl?: string;
}): Promise<SyncaMessage[]> {
    let query = db.selectFrom('messages')
        .selectAll()
        .where('user_id', '=', params.userId);

    if (params.since) {
        query = query.where('updated_at', '>', params.since);
    } else {
        // Initial load: skip deleted records
        query = query.where('is_deleted', '=', 0);
    }

    query = query.orderBy('created_at', 'asc');

    if (params.limit) {
        query = query.limit(params.limit);
    }

    const rows = await query.execute();
    return rows.map((row) => toMessage(row, params.baseUrl));
}

export async function getMessage(id: string, baseUrl?: string): Promise<SyncaMessage | undefined> {
    const row = await db.selectFrom('messages')
        .selectAll()
        .where('id', '=', id)
        .executeTakeFirst();
    return row ? toMessage(row, baseUrl) : undefined;
}

export async function createMessage(message: {
    id: string;
    userId: string;
    type: 'text' | 'image';
    textContent?: string | null;
    imagePath?: string | null;
    sourceDevice?: string | null;
    now: string;
}): Promise<void> {
    await db.insertInto('messages').values({
        id: message.id,
        user_id: message.userId,
        type: message.type,
        text_content: message.textContent ?? null,
        image_path: message.imagePath ?? null,
        is_cleared: 0,
        is_deleted: 0,
        source_device: message.sourceDevice ?? null,
        created_at: message.now,
        updated_at: message.now,
    }).execute();
}

export async function clearMessage(id: string, userId: string): Promise<boolean> {
    const now = new Date().toISOString();
    const result = await db.updateTable('messages')
        .set({ is_cleared: 1, updated_at: now })
        .where('id', '=', id)
        .where('user_id', '=', userId)
        .where('is_cleared', '=', 0)
        .execute();
    return result[0].numUpdatedRows > 0n;
}

export async function deleteMessage(id: string, userId: string, uploadsDir: string): Promise<boolean> {
    const now = new Date().toISOString();
    
    // 1. Get message info to check for image file
    const msg = await db.selectFrom('messages')
        .select(['id', 'image_path'])
        .where('id', '=', id)
        .where('user_id', '=', userId)
        .executeTakeFirst();
    
    if (!msg) return false;

    // 2. Mark as deleted in DB
    const result = await db.updateTable('messages')
        .set({ 
            is_deleted: 1, 
            updated_at: now,
            text_content: null, // Clear content for privacy
            image_path: null 
        })
        .where('id', '=', id)
        .where('user_id', '=', userId)
        .execute();
    
    const success = result[0].numUpdatedRows > 0n;

    // 3. Physically delete image file from disk if it exists
    if (success && msg.image_path) {
        import('fs').then((fs) => {
            const filePath = import('path').then((path) => {
                const fullPath = path.resolve(uploadsDir, msg.image_path!);
                fs.unlink(fullPath, (err) => {
                    if (err) console.error(`[delete] Failed to remove file ${fullPath}:`, err);
                    else console.log(`[delete] Physically removed file ${fullPath}`);
                });
            });
        });
    }

    return success;
}

export async function clearAllMessages(userId: string): Promise<number> {
    const now = new Date().toISOString();
    const result = await db.updateTable('messages')
        .set({ is_cleared: 1, updated_at: now })
        .where('user_id', '=', userId)
        .where('is_cleared', '=', 0)
        .execute();
    return Number(result[0].numUpdatedRows);
}

export async function deleteCompletedMessages(userId: string): Promise<number> {
    const result = await db.deleteFrom('messages')
        .where('user_id', '=', userId)
        .where('is_cleared', '=', 1)
        .execute();
    return Number(result[0].numDeletedRows);
}

export async function getUnclearedCount(userId: string): Promise<number> {
    const row = await db.selectFrom('messages')
        .select((eb) => eb.fn.count<string>('id').as('count'))
        .where('user_id', '=', userId)
        .where('is_cleared', '=', 0)
        .executeTakeFirst();
    return Number(row?.count ?? 0);
}

export async function countMessagesCreatedBetween(userId: string, startInclusive: string, endExclusive: string): Promise<number> {
    const row = await db.selectFrom('messages')
        .select((eb) => eb.fn.count<string>('id').as('count'))
        .where('user_id', '=', userId)
        .where('created_at', '>=', startInclusive)
        .where('created_at', '<', endExclusive)
        .executeTakeFirst();
    return Number(row?.count ?? 0);
}

// ── Session DAO ──

export async function createSession(token: string, userId: string, deviceId?: string): Promise<void> {
    const now = new Date().toISOString();
    await db.insertInto('sessions').values({
        token,
        user_id: userId,
        device_id: deviceId ?? null,
        created_at: now,
    }).execute();
}

export async function getSession(token: string): Promise<string | undefined> {
    const row = await db.selectFrom('sessions')
        .select('user_id')
        .where('token', '=', token)
        .executeTakeFirst();
    return row?.user_id;
}

// ── Device Push Token DAO ──

export type DevicePushTokenRecord = {
    id: string;
    userId: string;
    platform: string;
    token: string;
    apnsEnvironment: 'production' | 'sandbox';
    topic?: string;
    isActive: number;
    lastError?: string;
    lastSentAt?: string;
    createdAt: string;
    updatedAt: string;
};

export async function upsertDevicePushToken(input: {
    id: string;
    userId: string;
    platform: string;
    token: string;
    apnsEnvironment: 'production' | 'sandbox';
    topic?: string;
    now: string;
}): Promise<void> {
    await db.insertInto('device_push_tokens')
        .values({
            id: input.id,
            user_id: input.userId,
            platform: input.platform,
            token: input.token,
            apns_environment: input.apnsEnvironment,
            topic: input.topic ?? null,
            is_active: 1,
            last_error: null,
            last_sent_at: null,
            created_at: input.now,
            updated_at: input.now,
        })
        .onConflict((oc) => oc.column('token').doUpdateSet({
            user_id: input.userId,
            platform: input.platform,
            apns_environment: input.apnsEnvironment,
            topic: input.topic ?? null,
            is_active: 1,
            last_error: null,
            updated_at: input.now,
        }))
        .execute();
}

export async function listActiveDevicePushTokens(userId: string): Promise<DevicePushTokenRecord[]> {
    const rows = await db.selectFrom('device_push_tokens')
        .selectAll()
        .where('user_id', '=', userId)
        .where('is_active', '=', 1)
        .execute();

    return rows.map((row) => ({
        id: row.id,
        userId: row.user_id,
        platform: row.platform,
        token: row.token,
        apnsEnvironment: (row.apns_environment as 'production' | 'sandbox') ?? 'production',
        topic: row.topic ?? undefined,
        isActive: row.is_active,
        lastError: row.last_error ?? undefined,
        lastSentAt: row.last_sent_at ?? undefined,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    }));
}

export async function markDevicePushTokenStatus(input: {
    token: string;
    isActive: boolean;
    lastError?: string;
    lastSentAt?: string;
    now: string;
}): Promise<void> {
    await db.updateTable('device_push_tokens')
        .set({
            is_active: input.isActive ? 1 : 0,
            last_error: input.lastError ?? null,
            last_sent_at: input.lastSentAt ?? null,
            updated_at: input.now,
        })
        .where('token', '=', input.token)
        .execute();
}

export async function updateDevicePushTokenEnvironment(input: {
    token: string;
    apnsEnvironment: 'production' | 'sandbox';
    now: string;
}): Promise<void> {
    await db.updateTable('device_push_tokens')
        .set({
            apns_environment: input.apnsEnvironment,
            updated_at: input.now,
        })
        .where('token', '=', input.token)
        .execute();
}

// ── Reset (test only) ──

export async function resetDb() {
    await db.deleteFrom('iap_transactions').execute();
    await db.deleteFrom('device_push_tokens').execute();
    await db.deleteFrom('messages').execute();
    await db.deleteFrom('sessions').execute();
    await db.deleteFrom('users').execute();
}
