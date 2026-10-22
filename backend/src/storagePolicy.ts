import { sql } from 'kysely';
import { db } from './db.js';

export const IMAGE_LIMIT = 50 * 1024 * 1024;
export const FILE_LIMIT = 200 * 1024 * 1024;
export function storagePolicy(paid: boolean) {
    return { limitBytes: (paid ? 2048 : 200) * 1024 * 1024, imageLimitBytes: IMAGE_LIMIT,
        fileLimitBytes: paid ? FILE_LIMIT : 0, retentionDays: paid ? 7 : 3, canUploadFiles: paid };
}
export async function storageUsage(userId: string) {
    const result = await sql<{ bytes: number }>`SELECT COALESCE(SUM(file_size), 0) AS bytes FROM messages
        WHERE user_id = ${userId} AND is_deleted = 0 AND attachment_purged = 0 AND type IN ('image','file')`.execute(db);
    return Number(result.rows[0].bytes);
}

