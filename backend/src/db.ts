import SQLite from 'better-sqlite3';
import { Kysely, SqliteDialect } from 'kysely';
import { Database } from './db_types.js';
import path from 'path';
import fs from 'fs';

// Ensure data directory exists
const dataDir = path.resolve(process.cwd(), 'data');
if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
}

const configuredPath = process.env.DB_PATH?.trim();
const dbPath = configuredPath
    ? (path.isAbsolute(configuredPath) ? configuredPath : path.resolve(dataDir, configuredPath))
    : path.resolve(dataDir, 'synca.sqlite');

const dialect = new SqliteDialect({
    database: new SQLite(dbPath),
});

export const db = new Kysely<Database>({
    dialect,
});
