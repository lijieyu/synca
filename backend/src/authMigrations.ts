import { sql } from 'kysely';
import { db } from './db.js';

/** SQLite cannot remove NOT NULL in place. Preserve the original schema, columns,
 * indexes and triggers; only Apple identity becomes optional. Run before serving. */
export async function migrateLoginIdentities() {
    const columns = await sql<{ name: string; notnull: number }>`PRAGMA table_info(users)`.execute(db);
    if (columns.rows.some(c => c.name === 'apple_user_id' && c.notnull === 1)) {
        await db.connection().execute(async connection => {
            const fk = (await sql<{ foreign_keys: number }>`PRAGMA foreign_keys`.execute(connection)).rows[0]?.foreign_keys;
            await sql`PRAGMA foreign_keys=OFF`.execute(connection);
            try {
                await connection.transaction().execute(async trx => {
                    const schema = (await sql<{ sql: string }>`SELECT sql FROM sqlite_master WHERE type='table' AND name='users'`.execute(trx)).rows[0]?.sql;
                    if (!schema || !/apple_user_id\s+TEXT\s+UNIQUE\s+NOT NULL/i.test(schema)) throw new Error('Unsupported users schema; migration requires review');
                    const objects = await sql<{ sql: string }>`SELECT sql FROM sqlite_master WHERE tbl_name='users' AND type IN ('index','trigger') AND sql IS NOT NULL`.execute(trx);
                    const replacement = schema.replace(/^CREATE TABLE\s+(?:IF NOT EXISTS\s+)?["`]?users["`]?/i, 'CREATE TABLE users_email_v1')
                        .replace(/(apple_user_id\s+TEXT\s+UNIQUE)\s+NOT NULL/i, '$1');
                    if (replacement === schema) throw new Error('Unsupported users table name');
                    await sql.raw(replacement).execute(trx);
                    await sql`INSERT INTO users_email_v1 SELECT * FROM users`.execute(trx);
                    await sql`DROP TABLE users`.execute(trx);
                    await sql`ALTER TABLE users_email_v1 RENAME TO users`.execute(trx);
                    for (const object of objects.rows) await sql.raw(object.sql).execute(trx);
                    const invalid = await sql`PRAGMA foreign_key_check`.execute(trx);
                    if (invalid.rows.length) throw new Error('Foreign key check failed; rolled back users migration');
                });
            } finally {
                await sql.raw(`PRAGMA foreign_keys=${fk ? 'ON' : 'OFF'}`).execute(connection);
            }
        });
    }
    await sql`CREATE TABLE IF NOT EXISTS email_identities (
        email TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL
    )`.execute(db);
    await sql`CREATE TABLE IF NOT EXISTS email_auth_challenges (
        id TEXT PRIMARY KEY, email TEXT NOT NULL, purpose TEXT NOT NULL,
        user_id TEXT REFERENCES users(id) ON DELETE CASCADE, session_hash TEXT,
        code_hash TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
        resend_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL
    )`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_email_challenge_scope ON email_auth_challenges(email,purpose,user_id,created_at)`.execute(db);
    await sql`CREATE INDEX IF NOT EXISTS idx_email_challenge_expiry ON email_auth_challenges(expires_at)`.execute(db);
    await sql`CREATE TABLE IF NOT EXISTS apple_binding_challenges (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        session_hash TEXT NOT NULL, nonce TEXT NOT NULL, expires_at INTEGER NOT NULL, consumed INTEGER NOT NULL DEFAULT 0
    )`.execute(db);
    await sql`CREATE TABLE IF NOT EXISTS auth_rate_limits (
        bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL
    )`.execute(db);
}
