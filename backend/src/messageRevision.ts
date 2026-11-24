import { sql } from 'kysely';

/** One account's commit watermark, also usable by existing timestamp-based clients.
 * Evaluate inside the write: a delayed request or backwards clock must never put
 * a committed change behind a cursor another device has already observed.
 */
export function nextMessageTimestamp(now: string, userId?: string) {
    const owner = userId === undefined ? sql.ref('messages.user_id') : sql`${userId}`;
    return sql<string>`MAX(${now}, COALESCE(strftime('%Y-%m-%dT%H:%M:%fZ',
        (SELECT MAX(revision.updated_at) FROM messages AS revision WHERE revision.user_id = ${owner}),
        '+0.001 seconds'), ${now}))`;
}
