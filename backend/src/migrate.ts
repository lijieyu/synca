import { db } from './db.js';
import { sql } from 'kysely';

export async function runMigrations() {
    console.log('[migrate] Running database migrations...');

    // Create users table
    await sql`
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            apple_user_id TEXT UNIQUE NOT NULL,
            email TEXT,
            nickname TEXT NOT NULL DEFAULT 'Synca 用户',
            trial_started_at TEXT,
            trial_ends_at TEXT,
            purchase_date TEXT,
            subscription_expires_at TEXT,
            lifetime_purchased_at TEXT,
            store_product_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);

    try {
        await sql`ALTER TABLE users ADD COLUMN trial_started_at TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE users ADD COLUMN trial_ends_at TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE users ADD COLUMN purchase_date TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE users ADD COLUMN subscription_expires_at TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE users ADD COLUMN lifetime_purchased_at TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE users ADD COLUMN store_product_id TEXT`.execute(db);
    } catch (_e) {}

    try {
        await sql`ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0`.execute(db);
    } catch (_e) {}

    // Set initial admin
    try {
        await sql`UPDATE users SET is_admin = 1 WHERE email = 'jieyu.li@icloud.com'`.execute(db);
        console.log('[migrate] Ensured jieyu.li@icloud.com is admin.');
    } catch (_e) {}

    await sql`
        CREATE TABLE IF NOT EXISTS message_categories (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL REFERENCES users(id),
            name TEXT NOT NULL,
            color TEXT NOT NULL DEFAULT 'slate',
            is_default INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_message_categories_user_id ON message_categories(user_id)`.execute(db);
    await sql`CREATE UNIQUE INDEX IF NOT EXISTS idx_message_categories_user_name ON message_categories(user_id, name)`.execute(db);

    await sql`
        INSERT INTO message_categories (id, user_id, name, color, is_default, created_at, updated_at)
        SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' ||
               substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
               users.id,
               'Default',
               'slate',
               1,
               users.created_at,
               users.updated_at
        FROM users
        WHERE NOT EXISTS (
            SELECT 1 FROM message_categories
            WHERE message_categories.user_id = users.id
              AND message_categories.is_default = 1
        )
    `.execute(db);

    // Create messages table
    await sql`
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL REFERENCES users(id),
            type TEXT NOT NULL CHECK(type IN ('text', 'image', 'file')),
            text_content TEXT,
            image_path TEXT,
            file_path TEXT,
            file_name TEXT,
            file_size INTEGER,
            file_mime_type TEXT,
            category_id TEXT REFERENCES message_categories(id),
            is_cleared INTEGER NOT NULL DEFAULT 0,
            source_device TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);

    let shouldRebuildMessagesTable = false;
    try {
        await sql`ALTER TABLE messages ADD COLUMN file_path TEXT`.execute(db);
        shouldRebuildMessagesTable = true;
    } catch (_e) {}
    try {
        await sql`ALTER TABLE messages ADD COLUMN file_name TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE messages ADD COLUMN file_size INTEGER`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE messages ADD COLUMN file_mime_type TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE messages ADD COLUMN category_id TEXT REFERENCES message_categories(id)`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE messages ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0`.execute(db);
        console.log('[migrate] Added is_deleted column to messages table.');
    } catch (_e) {}

    if (shouldRebuildMessagesTable) {
        await sql`PRAGMA foreign_keys = OFF`.execute(db);
        await sql`
            CREATE TABLE IF NOT EXISTS messages_new (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL REFERENCES users(id),
                type TEXT NOT NULL CHECK(type IN ('text', 'image', 'file')),
                text_content TEXT,
                image_path TEXT,
                file_path TEXT,
                file_name TEXT,
                file_size INTEGER,
                file_mime_type TEXT,
                category_id TEXT REFERENCES message_categories(id),
                is_cleared INTEGER NOT NULL DEFAULT 0,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                source_device TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        `.execute(db);
        await sql`
            INSERT INTO messages_new (
                id, user_id, type, text_content, image_path, file_path, file_name, file_size, file_mime_type,
                category_id, is_cleared, is_deleted, source_device, created_at, updated_at
            )
            SELECT
                id, user_id, type, text_content, image_path, file_path, file_name, file_size, file_mime_type,
                category_id, is_cleared, COALESCE(is_deleted, 0), source_device, created_at, updated_at
            FROM messages
        `.execute(db);
        await sql`DROP TABLE messages`.execute(db);
        await sql`ALTER TABLE messages_new RENAME TO messages`.execute(db);
        await sql`PRAGMA foreign_keys = ON`.execute(db);
    }

    await sql`
        UPDATE messages
        SET category_id = (
            SELECT message_categories.id
            FROM message_categories
            WHERE message_categories.user_id = messages.user_id
              AND message_categories.is_default = 1
            LIMIT 1
        )
        WHERE category_id IS NULL
    `.execute(db);

    await sql`CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_messages_user_created ON messages(user_id, created_at)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_messages_category_id ON messages(category_id)`.execute(db);
    
    await sql`
        CREATE TABLE IF NOT EXISTS message_usage_events (
            message_id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL REFERENCES users(id),
            created_at TEXT NOT NULL,
            recorded_at TEXT NOT NULL
        )
    `.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_message_usage_events_user_created ON message_usage_events(user_id, created_at)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_message_usage_events_created_at ON message_usage_events(created_at)`.execute(db);
    await sql`
        INSERT OR IGNORE INTO message_usage_events (message_id, user_id, created_at, recorded_at)
        SELECT id, user_id, created_at, created_at
        FROM messages
    `.execute(db);

    // Create sessions table
    await sql`
        CREATE TABLE IF NOT EXISTS sessions (
            token TEXT PRIMARY KEY,
            user_id TEXT NOT NULL REFERENCES users(id),
            device_id TEXT,
            created_at TEXT NOT NULL
        )
    `.execute(db);

    // Create device_push_tokens table
    await sql`
        CREATE TABLE IF NOT EXISTS device_push_tokens (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL REFERENCES users(id),
            platform TEXT NOT NULL,
            token TEXT UNIQUE NOT NULL,
            apns_environment TEXT NOT NULL DEFAULT 'production',
            topic TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            last_error TEXT,
            last_sent_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);

    await sql`
        CREATE TABLE IF NOT EXISTS iap_transactions (
            transaction_id TEXT PRIMARY KEY,
            original_transaction_id TEXT,
            user_id TEXT NOT NULL REFERENCES users(id),
            product_id TEXT NOT NULL,
            environment TEXT NOT NULL,
            type TEXT,
            app_account_token TEXT,
            purchase_date TEXT,
            original_purchase_date TEXT,
            expires_at TEXT,
            revocation_date TEXT,
            is_upgraded INTEGER NOT NULL DEFAULT 0,
            signed_transaction_info TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_iap_transactions_user_id ON iap_transactions(user_id)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_iap_transactions_product_id ON iap_transactions(product_id)`.execute(db);

    await sql`
        CREATE TABLE IF NOT EXISTS feedbacks (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL REFERENCES users(id),
            content TEXT NOT NULL,
            email TEXT NOT NULL,
            image_paths TEXT,
            device_model TEXT,
            os_version TEXT,
            app_version TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);
    
    try {
        await sql`ALTER TABLE feedbacks ADD COLUMN device_model TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE feedbacks ADD COLUMN os_version TEXT`.execute(db);
    } catch (_e) {}
    try {
        await sql`ALTER TABLE feedbacks ADD COLUMN app_version TEXT`.execute(db);
    } catch (_e) {}

    await sql`CREATE INDEX IF NOT EXISTS idx_feedbacks_user_id ON feedbacks(user_id)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_feedbacks_created_at ON feedbacks(created_at)`.execute(db);

    await sql`
        CREATE TABLE IF NOT EXISTS lifetime_upgrade_offer_codes (
            id TEXT PRIMARY KEY,
            offer_kind TEXT NOT NULL CHECK(offer_kind IN ('monthly_to_lifetime', 'yearly_to_lifetime')),
            code TEXT UNIQUE NOT NULL,
            assigned_user_id TEXT REFERENCES users(id),
            assigned_at TEXT,
            redeemed_at TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_lifetime_offer_codes_kind ON lifetime_upgrade_offer_codes(offer_kind)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_lifetime_offer_codes_assigned_user ON lifetime_upgrade_offer_codes(assigned_user_id)`.execute(db);

    console.log('[migrate] Migrations complete.');
}

// Run migrations directly when executed as a script
const isDirectRun = process.argv[1]?.endsWith('migrate.js') || process.argv[1]?.endsWith('migrate.ts');
if (isDirectRun) {
    runMigrations().then(() => process.exit(0)).catch((err) => {
        console.error('[migrate] Failed:', err);
        process.exit(1);
    });
}
