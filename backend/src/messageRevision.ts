import { sql } from 'kysely';

/** ISO millisecond timestamps also serve as optimistic-concurrency revisions.
 * Advance each affected row even when the clock is frozen or a prior edit ran ahead of it.
 */
export function nextMessageTimestamp(now: string) {
    return sql<string>`MAX(${now}, strftime('%Y-%m-%dT%H:%M:%fZ', updated_at, '+0.001 seconds'))`;
}
