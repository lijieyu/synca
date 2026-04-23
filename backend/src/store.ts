import { db } from './db.js';
import { sql } from 'kysely';
import { v4 as uuidv4 } from 'uuid';
import { SyncaUser, SyncaMessage, SyncaLifetimeUpgradeOfferKind, SyncaMessageCategory, SyncaMessageCategoryColor } from './types.js';
import { UsersTable, MessagesTable, IapTransactionsTable, LifetimeUpgradeOfferCodesTable, MessageCategoriesTable } from './db_types.js';

// ── Mappers ──

function toUser(row: UsersTable): SyncaUser {
    return {
        id: row.id,
        appleUserId: row.apple_user_id,
        email: row.email ?? undefined,
        nickname: row.nickname,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        isAdmin: row.is_admin === 1,
    };
}

function toMessage(row: MessagesTable, baseUrl?: string): SyncaMessage {
    return {
        id: row.id,
        userId: row.user_id,
        type: row.type as 'text' | 'image' | 'file',
        textContent: row.text_content ?? undefined,
        imagePath: row.image_path ?? undefined,
        imageUrl: row.image_path && baseUrl ? `${baseUrl}/api/media/${row.image_path}` : undefined,
        filePath: row.file_path ?? undefined,
        fileUrl: row.file_path && baseUrl ? `${baseUrl}/api/media/${row.file_path}` : undefined,
        fileName: row.file_name ?? undefined,
        fileSize: row.file_size ?? undefined,
        fileMimeType: row.file_mime_type ?? undefined,
        categoryId: row.category_id ?? undefined,
        isCleared: row.is_cleared === 1,
        isDeleted: row.is_deleted === 1,
        sourceDevice: row.source_device ?? undefined,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    };
}

function toCategory(row: MessageCategoriesTable): SyncaMessageCategory {
    return {
        id: row.id,
        userId: row.user_id,
        name: row.name,
        color: row.color as SyncaMessageCategoryColor,
        isDefault: row.is_default === 1,
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

export async function updateUserEmail(userId: string, email: string, now: string): Promise<SyncaUser | undefined> {
    await db.updateTable('users')
        .set({
            email,
            updated_at: now,
        })
        .where('id', '=', userId)
        .execute();

    return getUser(userId);
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
        is_admin: 0,
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

export async function countAvailableLifetimeUpgradeCodes(kind: SyncaLifetimeUpgradeOfferKind): Promise<number> {
    const result = await db.selectFrom('lifetime_upgrade_offer_codes')
        .select(({ fn }) => fn.count<string>('id').as('count'))
        .where('offer_kind', '=', kind)
        .where('is_active', '=', 1)
        .where('redeemed_at', 'is', null)
        .where('assigned_user_id', 'is', null)
        .executeTakeFirst();

    return Number(result?.count ?? 0);
}

export async function getAssignedLifetimeUpgradeCode(userId: string, kind: SyncaLifetimeUpgradeOfferKind): Promise<LifetimeUpgradeOfferCodesTable | undefined> {
    return db.selectFrom('lifetime_upgrade_offer_codes')
        .selectAll()
        .where('offer_kind', '=', kind)
        .where('assigned_user_id', '=', userId)
        .where('is_active', '=', 1)
        .where('redeemed_at', 'is', null)
        .orderBy('assigned_at', 'asc')
        .executeTakeFirst();
}

export async function assignLifetimeUpgradeCode(userId: string, kind: SyncaLifetimeUpgradeOfferKind, now: string): Promise<LifetimeUpgradeOfferCodesTable | undefined> {
    return db.transaction().execute(async (trx) => {
        const existing = await trx.selectFrom('lifetime_upgrade_offer_codes')
            .selectAll()
            .where('offer_kind', '=', kind)
            .where('assigned_user_id', '=', userId)
            .where('is_active', '=', 1)
            .where('redeemed_at', 'is', null)
            .orderBy('assigned_at', 'asc')
            .executeTakeFirst();

        if (existing) return existing;

        const candidate = await trx.selectFrom('lifetime_upgrade_offer_codes')
            .select(['id'])
            .where('offer_kind', '=', kind)
            .where('is_active', '=', 1)
            .where('redeemed_at', 'is', null)
            .where('assigned_user_id', 'is', null)
            .orderBy('created_at', 'asc')
            .executeTakeFirst();

        if (!candidate) return undefined;

        await trx.updateTable('lifetime_upgrade_offer_codes')
            .set({
                assigned_user_id: userId,
                assigned_at: now,
                updated_at: now,
            })
            .where('id', '=', candidate.id)
            .where('assigned_user_id', 'is', null)
            .execute();

        return trx.selectFrom('lifetime_upgrade_offer_codes')
            .selectAll()
            .where('id', '=', candidate.id)
            .where('assigned_user_id', '=', userId)
            .executeTakeFirst();
    });
}

export async function markAssignedLifetimeUpgradeCodesRedeemed(userId: string, now: string): Promise<void> {
    await db.updateTable('lifetime_upgrade_offer_codes')
        .set({
            redeemed_at: now,
            updated_at: now,
        })
        .where('assigned_user_id', '=', userId)
        .where('redeemed_at', 'is', null)
        .execute();
}

export async function importLifetimeUpgradeCodes(input: {
    kind: SyncaLifetimeUpgradeOfferKind;
    codes: string[];
    now: string;
}): Promise<{ inserted: number; existing: number }> {
    const uniqueCodes = Array.from(
        new Set(
            input.codes
                .map((code) => code.trim())
                .filter((code) => code.length > 0)
        )
    );

    if (uniqueCodes.length === 0) {
        return { inserted: 0, existing: 0 };
    }

    let inserted = 0;
    let existing = 0;

    for (const code of uniqueCodes) {
        const result = await db.insertInto('lifetime_upgrade_offer_codes')
            .values({
                id: uuidv4(),
                offer_kind: input.kind,
                code,
                assigned_user_id: null,
                assigned_at: null,
                redeemed_at: null,
                is_active: 1,
                created_at: input.now,
                updated_at: input.now,
            })
            .onConflict((oc) => oc.column('code').doNothing())
            .executeTakeFirst();

        const affectedRows = Number(result.numInsertedOrUpdatedRows ?? 0);
        if (affectedRows > 0) {
            inserted += 1;
        } else {
            existing += 1;
        }
    }

    return { inserted, existing };
}

export async function createFeedback(input: {
    id: string;
    userId: string;
    content: string;
    email: string;
    imagePaths: string[];
    now: string;
}): Promise<void> {
    await db.insertInto('feedbacks').values({
        id: input.id,
        user_id: input.userId,
        content: input.content,
        email: input.email,
        image_paths: input.imagePaths.length > 0 ? JSON.stringify(input.imagePaths) : null,
        device_model: (input as any).deviceModel ?? null,
        os_version: (input as any).osVersion ?? null,
        app_version: (input as any).appVersion ?? null,
        created_at: input.now,
        updated_at: input.now,
    }).execute();
}

// ── Message Category DAO ──

async function ensureDefaultCategory(userId: string, now = new Date().toISOString()): Promise<MessageCategoriesTable> {
    const existing = await db.selectFrom('message_categories')
        .selectAll()
        .where('user_id', '=', userId)
        .where('is_default', '=', 1)
        .executeTakeFirst();

    if (existing) {
        return existing;
    }

    const id = uuidv4();
    await db.insertInto('message_categories').values({
        id,
        user_id: userId,
        name: 'Default',
        color: 'slate',
        is_default: 1,
        created_at: now,
        updated_at: now,
    }).execute();

    return (await db.selectFrom('message_categories')
        .selectAll()
        .where('id', '=', id)
        .executeTakeFirst())!;
}

export async function listMessageCategories(userId: string): Promise<SyncaMessageCategory[]> {
    await ensureDefaultCategory(userId);

    const rows = await db.selectFrom('message_categories')
        .selectAll()
        .where('user_id', '=', userId)
        .orderBy('is_default', 'desc')
        .orderBy('created_at', 'asc')
        .execute();

    return rows.map(toCategory);
}

export async function createMessageCategory(input: {
    userId: string;
    name: string;
    color: SyncaMessageCategoryColor;
    now: string;
}): Promise<SyncaMessageCategory> {
    const id = uuidv4();
    await db.insertInto('message_categories').values({
        id,
        user_id: input.userId,
        name: input.name,
        color: input.color,
        is_default: 0,
        created_at: input.now,
        updated_at: input.now,
    }).execute();

    const row = await db.selectFrom('message_categories')
        .selectAll()
        .where('id', '=', id)
        .executeTakeFirstOrThrow();

    return toCategory(row);
}

export async function updateMessageCategory(input: {
    id: string;
    userId: string;
    name?: string;
    color?: SyncaMessageCategoryColor;
    now: string;
}): Promise<SyncaMessageCategory | undefined> {
    const existing = await db.selectFrom('message_categories')
        .selectAll()
        .where('id', '=', input.id)
        .where('user_id', '=', input.userId)
        .executeTakeFirst();

    if (!existing || existing.is_default === 1) {
        return undefined;
    }

    await db.updateTable('message_categories')
        .set({
            name: input.name ?? existing.name,
            color: input.color ?? existing.color,
            updated_at: input.now,
        })
        .where('id', '=', input.id)
        .where('user_id', '=', input.userId)
        .execute();

    const row = await db.selectFrom('message_categories')
        .selectAll()
        .where('id', '=', input.id)
        .executeTakeFirst();

    return row ? toCategory(row) : undefined;
}

export async function deleteMessageCategory(input: {
    id: string;
    userId: string;
    now: string;
}): Promise<boolean> {
    const existing = await db.selectFrom('message_categories')
        .selectAll()
        .where('id', '=', input.id)
        .where('user_id', '=', input.userId)
        .executeTakeFirst();

    if (!existing || existing.is_default === 1) {
        return false;
    }

    const defaultCategory = await ensureDefaultCategory(input.userId, input.now);

    await db.transaction().execute(async (trx) => {
        await trx.updateTable('messages')
            .set({
                category_id: defaultCategory.id,
                updated_at: input.now,
            })
            .where('user_id', '=', input.userId)
            .where('category_id', '=', input.id)
            .execute();

        await trx.deleteFrom('message_categories')
            .where('id', '=', input.id)
            .where('user_id', '=', input.userId)
            .execute();
    });

    return true;
}

async function resolveCategoryId(userId: string, categoryId: string | null | undefined, now: string): Promise<string> {
    if (!categoryId) {
        return (await ensureDefaultCategory(userId, now)).id;
    }

    const category = await db.selectFrom('message_categories')
        .select(['id'])
        .where('id', '=', categoryId)
        .where('user_id', '=', userId)
        .executeTakeFirst();

    if (category) {
        return category.id;
    }

    return (await ensureDefaultCategory(userId, now)).id;
}

export async function updateMessageCategoryAssignment(input: {
    id: string;
    userId: string;
    categoryId?: string | null;
    now: string;
    baseUrl?: string;
}): Promise<SyncaMessage | undefined> {
    const resolvedCategoryId = await resolveCategoryId(input.userId, input.categoryId, input.now);
    const result = await db.updateTable('messages')
        .set({
            category_id: resolvedCategoryId,
            updated_at: input.now,
        })
        .where('id', '=', input.id)
        .where('user_id', '=', input.userId)
        .execute();

    if (result[0].numUpdatedRows === 0n) {
        return undefined;
    }

    return getMessage(input.id, input.baseUrl);
}

// ── Message DAO ──

export async function listMessages(params: {
    userId: string;
    since?: string;
    limit?: number;
    baseUrl?: string;
}): Promise<SyncaMessage[]> {
    await ensureDefaultCategory(params.userId);

    let query = db.selectFrom('messages')
        .leftJoin('message_categories', 'message_categories.id', 'messages.category_id')
        .selectAll('messages')
        .select([
            'message_categories.name as category_name',
            'message_categories.color as category_color',
            'message_categories.is_default as category_is_default',
        ])
        .where('messages.user_id', '=', params.userId);

    if (params.since) {
        query = query.where('messages.updated_at', '>', params.since);
    } else {
        // Initial load: skip deleted records
        query = query.where('messages.is_deleted', '=', 0);
    }

    query = query.orderBy('messages.created_at', 'asc');

    if (params.limit) {
        query = query.limit(params.limit);
    }

    const rows = await query.execute();
    return rows.map((row: any) => ({
        ...toMessage(row, params.baseUrl),
        categoryName: row.category_name ?? undefined,
        categoryColor: row.category_color ?? undefined,
        categoryIsDefault: row.category_is_default === 1,
    }));
}

export async function getMessage(id: string, baseUrl?: string): Promise<SyncaMessage | undefined> {
    const row = await db.selectFrom('messages')
        .leftJoin('message_categories', 'message_categories.id', 'messages.category_id')
        .selectAll('messages')
        .select([
            'message_categories.name as category_name',
            'message_categories.color as category_color',
            'message_categories.is_default as category_is_default',
        ])
        .where('messages.id', '=', id)
        .executeTakeFirst();
    return row ? {
        ...toMessage(row as any, baseUrl),
        categoryName: (row as any).category_name ?? undefined,
        categoryColor: (row as any).category_color ?? undefined,
        categoryIsDefault: (row as any).category_is_default === 1,
    } : undefined;
}

export async function createMessage(message: {
    id: string;
    userId: string;
    type: 'text' | 'image' | 'file';
    textContent?: string | null;
    imagePath?: string | null;
    filePath?: string | null;
    fileName?: string | null;
    fileSize?: number | null;
    fileMimeType?: string | null;
    categoryId?: string | null;
    sourceDevice?: string | null;
    now: string;
}): Promise<void> {
    const resolvedCategoryId = await resolveCategoryId(message.userId, message.categoryId, message.now);
    await db.transaction().execute(async (trx) => {
        await trx.insertInto('messages').values({
            id: message.id,
            user_id: message.userId,
            type: message.type,
            text_content: message.textContent ?? null,
            image_path: message.imagePath ?? null,
            file_path: message.filePath ?? null,
            file_name: message.fileName ?? null,
            file_size: message.fileSize ?? null,
            file_mime_type: message.fileMimeType ?? null,
            category_id: resolvedCategoryId,
            is_cleared: 0,
            is_deleted: 0,
            source_device: message.sourceDevice ?? null,
            created_at: message.now,
            updated_at: message.now,
        }).execute();

        await trx.insertInto('message_usage_events').values({
            message_id: message.id,
            user_id: message.userId,
            created_at: message.now,
            recorded_at: message.now,
        }).execute();
    });
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

export async function deleteMessage(id: string, userId: string, uploadsDir: string, filesDir: string): Promise<boolean> {
    const now = new Date().toISOString();
    
    // 1. Get message info to check for stored media
    const msg = await db.selectFrom('messages')
        .select(['id', 'image_path', 'file_path'])
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
            image_path: null,
            file_path: null,
            file_name: null,
            file_size: null,
            file_mime_type: null,
        })
        .where('id', '=', id)
        .where('user_id', '=', userId)
        .execute();
    
    const success = result[0].numUpdatedRows > 0n;

    // 3. Physically delete stored media from disk if it exists
    if (success) {
        import('fs').then((fs) => {
            import('path').then((path) => {
                const mediaTargets = [
                    msg.image_path ? path.resolve(uploadsDir, msg.image_path) : null,
                    msg.file_path ? path.resolve(filesDir, msg.file_path) : null,
                ].filter((target): target is string => Boolean(target));

                mediaTargets.forEach((target) => {
                    fs.unlink(target, (err) => {
                        if (err) console.error(`[delete] Failed to remove file ${target}:`, err);
                        else console.log(`[delete] Physically removed file ${target}`);
                    });
                });
            });
        });
    }

    return success;
}

export async function clearAllMessages(userId: string, categoryId?: string | null): Promise<number> {
    const now = new Date().toISOString();
    let query = db.updateTable('messages')
        .set({ is_cleared: 1, updated_at: now })
        .where('user_id', '=', userId)
        .where('is_cleared', '=', 0);

    if (categoryId) {
        query = query.where('category_id', '=', categoryId);
    }

    const result = await query.execute();
    return Number(result[0].numUpdatedRows);
}

export async function deleteCompletedMessages(userId: string, uploadsDir: string, filesDir: string, categoryId?: string | null): Promise<number> {
    const now = new Date().toISOString();

    let completedQuery = db.selectFrom('messages')
        .select(['id', 'image_path', 'file_path'])
        .where('user_id', '=', userId)
        .where('is_cleared', '=', 1)
        .where('is_deleted', '=', 0);

    if (categoryId) {
        completedQuery = completedQuery.where('category_id', '=', categoryId);
    }

    const completedMessages = await completedQuery.execute();

    if (completedMessages.length === 0) {
        return 0;
    }

    const ids = completedMessages.map((message) => message.id);
    const imagePaths = completedMessages
        .map((message) => message.image_path)
        .filter((path): path is string => Boolean(path));
    const filePaths = completedMessages
        .map((message) => message.file_path)
        .filter((path): path is string => Boolean(path));

    const result = await db.updateTable('messages')
        .set({
            is_deleted: 1,
            updated_at: now,
            text_content: null,
            image_path: null,
            file_path: null,
            file_name: null,
            file_size: null,
            file_mime_type: null,
        })
        .where('user_id', '=', userId)
        .where('id', 'in', ids)
        .execute();

    if (imagePaths.length > 0 || filePaths.length > 0) {
        import('fs').then((fs) => {
            const targets = [
                ...imagePaths.map((imagePath) => uploadsDir + '/' + imagePath),
                ...filePaths.map((filePath) => filesDir + '/' + filePath),
            ];
            targets.forEach((fullPath) => {
                fs.unlink(fullPath, (err) => {
                    if (err) console.error(`[delete] Failed to remove file ${fullPath}:`, err);
                    else console.log(`[delete] Physically removed file ${fullPath}`);
                });
            });
        });
    }

    return Number(result[0].numUpdatedRows);
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
    const row = await db.selectFrom('message_usage_events')
        .select((eb) => eb.fn.count<string>('message_id').as('count'))
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

export async function canUserAccessMedia(userId: string, filename: string, isAdmin: boolean): Promise<boolean> {
    if (isAdmin) return true;

    // Check messages
    const messageHit = await db.selectFrom('messages')
        .select('id')
        .where('user_id', '=', userId)
        .where((eb) =>
            eb.or([
                eb('image_path', '=', filename),
                eb('file_path', '=', filename),
            ])
        )
        .where('is_deleted', '=', 0) // Deleted messages might not have image access
        .executeTakeFirst();
        
    if (messageHit) return true;

    // Check feedbacks (using LIKE is okay since we store ["filename.jpg"])
    const feedbackHit = await db.selectFrom('feedbacks')
        .select('id')
        .where('user_id', '=', userId)
        .where('image_paths', 'like', `%${filename}%`)
        .executeTakeFirst();

    return Boolean(feedbackHit);
}

export async function resetDb() {
    await db.deleteFrom('feedbacks').execute();
    await db.deleteFrom('iap_transactions').execute();
    await db.deleteFrom('device_push_tokens').execute();
    await db.deleteFrom('lifetime_upgrade_offer_codes').execute();
    await db.deleteFrom('message_usage_events').execute();
    await db.deleteFrom('messages').execute();
    await db.deleteFrom('sessions').execute();
    await db.deleteFrom('users').execute();
}

// ── Admin DAO ──

export async function getAdminOverviewStats() {
    const userCount = await db.selectFrom('users').select((eb) => eb.fn.countAll().as('count')).executeTakeFirst();
    const todoCount = await db.selectFrom('messages').select((eb) => eb.fn.countAll().as('count')).where('is_deleted', '=', 0).executeTakeFirst();
    const feedbackCount = await db.selectFrom('feedbacks').select((eb) => eb.fn.countAll().as('count')).executeTakeFirst();
    
    // Revenue calculation (¥6, ¥30, ¥98)
    const transactions = await db.selectFrom('iap_transactions')
        .select(['product_id'])
        .where('environment', '=', 'Production')
        .execute();
    let totalRevenue = 0;
    for (const tx of transactions) {
        if (tx.product_id.includes('monthly')) totalRevenue += 6;
        else if (tx.product_id.includes('yearly')) totalRevenue += 30;
        else if (tx.product_id.includes('lifetime')) totalRevenue += 98;
    }

    return {
        totalUsers: Number(userCount?.count ?? 0),
        totalTodos: Number(todoCount?.count ?? 0),
        totalFeedback: Number(feedbackCount?.count ?? 0),
        totalRevenue,
    };
}

export async function getAdminUserList() {
    // We join users with message counts and last activity
    const users = await db.selectFrom('users')
        .selectAll()
        .execute();

    const result = [];
    for (const u of users) {
        const msgCount = await db.selectFrom('messages')
            .select((eb) => eb.fn.countAll().as('count'))
            .where('user_id', '=', u.id)
            .where('is_deleted', '=', 0)
            .executeTakeFirst();
            
        const lastMsg = await db.selectFrom('messages')
            .select('created_at')
            .where('user_id', '=', u.id)
            .orderBy('created_at', 'desc')
            .executeTakeFirst();

        let plan = 'Free';
        if (u.lifetime_purchased_at) plan = 'Lifetime';
        else if (u.subscription_expires_at && new Date(u.subscription_expires_at) > new Date()) {
            plan = u.store_product_id?.includes('yearly') ? 'Yearly' : 'Monthly';
        }

        result.push({
            id: u.id,
            email: u.email,
            plan,
            todoCount: Number(msgCount?.count ?? 0),
            lastActive: lastMsg?.created_at ?? u.created_at,
            registeredAt: u.created_at,
        });
    }
    return result;
}

export async function getAdminMessageStats() {
    const dailyVolume = await db.selectFrom('messages')
        .select([
            sql<string>`date(created_at)`.as('date'),
            (eb) => eb.fn.countAll().as('count')
        ])
        .groupBy('date')
        .orderBy('date', 'desc')
        .limit(30)
        .execute();

    const typeDistribution = await db.selectFrom('messages')
        .select([
            'type',
            (eb) => eb.fn.countAll().as('count')
        ])
        .groupBy('type')
        .execute();

    return { 
        dailyVolume: dailyVolume.map(d => ({ date: d.date, count: Number(d.count) })),
        distribution: typeDistribution.map(t => ({ type: t.type, count: Number(t.count) }))
    };
}

export async function getAdminRevenueStats() {
    const transactions = await db.selectFrom('iap_transactions')
        .select(['product_id', 'purchase_date'])
        .where('environment', '=', 'Production')
        .execute();

    const dailyMap: Record<string, number> = {};
    for (const tx of transactions) {
        if (!tx.purchase_date) continue;
        const date = tx.purchase_date.split('T')[0];
        let price = 0;
        if (tx.product_id.includes('monthly')) price = 6;
        else if (tx.product_id.includes('yearly')) price = 30;
        else if (tx.product_id.includes('lifetime')) price = 98;
        
        dailyMap[date] = (dailyMap[date] || 0) + price;
    }

    const dailyRevenue = Object.entries(dailyMap)
        .map(([date, amount]) => ({ date, amount }))
        .sort((a, b) => b.date.localeCompare(a.date))
        .slice(0, 30);

    return { dailyRevenue };
}

export async function getAdminFeedbackList() {
    const rows = await db.selectFrom('feedbacks')
        .leftJoin('users', 'feedbacks.user_id', 'users.id')
        .select([
            'feedbacks.id',
            'feedbacks.content',
            'feedbacks.email',
            'feedbacks.device_model',
            'feedbacks.os_version',
            'feedbacks.app_version',
            'feedbacks.created_at',
            'users.email as userEmail'
        ])
        .orderBy('feedbacks.created_at', 'desc')
        .execute();

    return rows;
}
