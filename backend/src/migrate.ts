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
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);

    // Create messages table
    await sql`
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL REFERENCES users(id),
            type TEXT NOT NULL CHECK(type IN ('text', 'image')),
            text_content TEXT,
            image_path TEXT,
            is_cleared INTEGER NOT NULL DEFAULT 0,
            source_device TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    `.execute(db);

    await sql`CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_messages_user_created ON messages(user_id, created_at)`.execute(db);

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
