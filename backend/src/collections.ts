import type { Request } from 'express';
import { db } from './db.js';
import { getMessage } from './store.js';
import { nextMessageTimestamp } from './messageRevision.js';
import type { SyncaMessage } from './types.js';

export const supportsCollections = (request: Request) =>
    request.header('X-Synca-Features')?.split(',').map(value => value.trim()).includes('collections') === true;

/** Tombstones let old clients discard already cached tasks without exposing collection contents. */
export function legacyCollectionProjection(messages: SyncaMessage[], incremental: boolean): SyncaMessage[] {
    return messages.flatMap(message => !message.collectedAt ? [message] : incremental ? [{
        id: message.id, userId: message.userId, type: message.type,
        isDeleted: true, isCleared: false, createdAt: message.createdAt, updatedAt: message.updatedAt,
    }] : []);
}

export async function collectMessage(userId: string, id: string, expectedUpdatedAt: string, baseUrl?: string) {
    const error = await db.transaction().execute(async trx => {
        const row = await trx.selectFrom('messages').selectAll().where('id', '=', id)
            .where('user_id', '=', userId).where('is_deleted', '=', 0).executeTakeFirst();
        if (!row) return { error: 'message_not_found', status: 404 };
        if (row.collected_at) return null; // Retrying the one-way transition is safe.
        if (row.updated_at !== expectedUpdatedAt) return { error: 'message_edit_conflict', status: 409 };
        const now = new Date().toISOString();
        if (row.type !== 'text' && (row.attachment_purged ||
            (row.attachment_expires_at && row.attachment_expires_at <= now))) {
            return { error: 'attachment_expired', status: 410 };
        }
        await trx.updateTable('messages').set({ collected_at: now, is_cleared: 0,
            attachment_expires_at: null, updated_at: nextMessageTimestamp(now) })
            .where('id', '=', id).where('user_id', '=', userId).execute();
        return null;
    });
    return error ?? { message: (await getMessage(id, baseUrl))! };
}
