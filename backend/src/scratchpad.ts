import { randomUUID } from 'node:crypto';
import { db } from './db.js';
import { getMessage, purgeMessageMedia } from './store.js';
import { nextMessageTimestamp } from './messageRevision.js';

export const imageIDs = (content: string) => [...new Set([...content.matchAll(/synca-image:([0-9a-f-]{36})/gi)].map(match => match[1].toLowerCase()))];
const empty = { content: '', revision: 0, updatedAt: null as string | null };
export async function readScratchpad(userId: string) {
    const row = await db.selectFrom('scratchpads').selectAll().where('user_id', '=', userId).executeTakeFirst();
    return row ? { content: row.content, revision: row.revision, updatedAt: row.updated_at } : empty;
}
export async function writeScratchpad(userId: string, input: { content: string; expectedRevision: number; mutationId: string; preserveCurrent?: boolean }) {
    return db.transaction().execute(async trx => {
        const ids = imageIDs(input.content);
        if (ids.length) {
            const assets = await trx.selectFrom('messages').select('id').where('user_id', '=', userId)
                .where('scratchpad_asset', '=', 1).where('is_deleted', '=', 0).where('attachment_purged', '=', 0)
                .where('id', 'in', ids).execute();
            if (assets.length !== ids.length) return { status: 422, body: { error: 'scratchpad_image_missing' } };
        }
        const row = await trx.selectFrom('scratchpads').selectAll().where('user_id', '=', userId).executeTakeFirst();
        const current = row ? {content: row.content, revision: row.revision, updatedAt: row.updated_at} : empty;
        if (row?.mutation_id === input.mutationId || current.content === input.content) return {status: 200, body: current};
        const now = new Date().toISOString();
        if (current.revision !== input.expectedRevision) {
            await trx.insertInto('scratchpad_conflicts').values({id: input.mutationId, user_id: userId,
                content: input.content, created_at: now}).onConflict(oc => oc.columns(['user_id','id']).doNothing()).execute();
            return {status: 409, body: {error: 'scratchpad_conflict', current, conflictId: input.mutationId}};
        }
        if (input.preserveCurrent && row) {
            await trx.insertInto('scratchpad_conflicts').values({id:randomUUID(),user_id:userId,content:row.content,created_at:now}).execute();
        }
        const updated = {user_id: userId, content: input.content, revision: current.revision + 1, updated_at: now, mutation_id: input.mutationId};
        await trx.insertInto('scratchpads').values(updated).onConflict(oc => oc.column('user_id').doUpdateSet(updated)).execute();
        return {status: 200, body: {content: updated.content, revision: updated.revision, updatedAt: now}};
    });
}
// Save a recovery copy without ever writing the main page, even if another device advances it.
export async function preserveScratchpadCopy(userId: string, input: {content: string; mutationId: string}) {
    return db.transaction().execute(async trx => {
        await trx.insertInto('scratchpad_conflicts').values({id:input.mutationId,user_id:userId,
            content:input.content,created_at:new Date().toISOString()})
            .onConflict(oc=>oc.columns(['user_id','id']).doNothing()).execute();
        const row = await trx.selectFrom('scratchpads').selectAll().where('user_id','=',userId).executeTakeFirst();
        return row ? {content:row.content,revision:row.revision,updatedAt:row.updated_at} : empty;
    });
}
export async function scratchpadImages(userId: string, baseUrl: string) {
    const rows = await db.selectFrom('messages').select('id').where('user_id','=',userId)
        .where('scratchpad_asset','=',1).where('is_deleted','=',0).execute();
    return Promise.all(rows.map(row => getMessage(row.id, baseUrl)));
}
export async function deleteScratchpadImage(userId: string, id: string, uploadsDir: string, filesDir: string) {
    const result = await db.transaction().execute(async trx => {
        const row = await trx.selectFrom('messages').selectAll().where('user_id','=',userId).where('id','=',id)
            .where('scratchpad_asset','=',1).where('is_deleted','=',0).executeTakeFirst();
        if (!row) return {status: 404 as const};
        const main = await trx.selectFrom('scratchpads').select('content').where('user_id','=',userId).execute();
        const copies = await trx.selectFrom('scratchpad_conflicts').select('content').where('user_id','=',userId).execute();
        if ([...main,...copies].some(doc => imageIDs(doc.content).includes(id))) return {status: 409 as const};
        await trx.updateTable('messages').set({is_deleted:1,attachment_expires_at:new Date().toISOString(),updated_at:nextMessageTimestamp(new Date().toISOString())})
            .where('id','=',id).where('user_id','=',userId).execute();
        return {status:200 as const,row};
    });
    if (result.status === 200) {
        try { await purgeMessageMedia({...result.row!,is_deleted:1},uploadsDir,filesDir); }
        catch (error) { console.error('[scratchpad] media cleanup queued', id, error); }
    }
    return result.status;
}
