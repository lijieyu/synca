import type { Transaction } from 'kysely';
import type { Database } from './db_types.js';
import { db } from './db.js';
import { AIError, hash, secret, scopeSchema, publicOrigin } from './aiCore.js';

export const OAUTH_GRANT_DAYS = 365;
export const OAUTH_ACCESS_SECONDS = 3600;
export const OAUTH_REFRESH_IDLE_DAYS = 180;
const day = 86400000;

export async function issueOAuthTokens(trx: Transaction<Database>, connectionId: string, refresh: boolean) {
    const now = new Date();
    const connection = await trx.selectFrom('ai_connections').innerJoin('users', 'users.id', 'ai_connections.user_id')
        .selectAll('ai_connections').where('ai_connections.id', '=', connectionId).where('revoked_at', 'is', null)
        .where('expires_at', '>', now.toISOString()).executeTakeFirst();
    if (!connection) throw new AIError(400, 'invalid_grant');
    const seconds = Math.min(refresh ? OAUTH_ACCESS_SECONDS : 30 * 86400,
        Math.floor((Date.parse(connection.expires_at) - now.getTime()) / 1000));
    if (seconds < 1) throw new AIError(400, 'invalid_grant');
    const accessToken = `synca_ai_${secret()}`;
    await trx.updateTable('ai_connections').set({ token_hash: hash(accessToken),
        access_expires_at: new Date(now.getTime() + seconds * 1000).toISOString() }).where('id', '=', connectionId).execute();
    const refreshToken = refresh ? `synca_refresh_${secret()}` : undefined;
    if (refreshToken) await trx.insertInto('ai_refresh_tokens').values({ token_hash: hash(refreshToken), connection_id: connectionId,
        created_at: now.toISOString(), consumed_at: null,
        expires_at: new Date(Math.min(Date.parse(connection.expires_at), now.getTime() + OAUTH_REFRESH_IDLE_DAYS * day)).toISOString() }).execute();
    return { access_token: accessToken, token_type: 'Bearer', expires_in: seconds,
        scope: scopeSchema.parse(JSON.parse(connection.scopes)).join(' '), ...(refreshToken ? { refresh_token: refreshToken } : {}) };
}

export async function refreshOAuthTokens(clientId: string, token: string, resource?: string, scope?: string) {
    if (resource && resource !== `${publicOrigin()}/mcp`) throw new AIError(400, 'invalid_target');
    const result = await db.transaction().execute(async trx => {
        const row = await trx.selectFrom('ai_refresh_tokens').innerJoin('ai_connections', 'ai_connections.id', 'ai_refresh_tokens.connection_id')
            .innerJoin('users', 'users.id', 'ai_connections.user_id')
            .select(['ai_refresh_tokens.token_hash', 'ai_refresh_tokens.consumed_at', 'ai_refresh_tokens.expires_at as refreshExpiry',
                'ai_connections.id', 'ai_connections.scopes', 'ai_connections.expires_at', 'ai_connections.revoked_at'])
            .where('ai_refresh_tokens.token_hash', '=', hash(token)).where('ai_connections.client_id', '=', clientId).executeTakeFirst();
        const now = new Date().toISOString();
        if (!row || row.revoked_at || row.expires_at <= now) return null;
        // Commit revocation on replay: throwing here would roll the revocation back.
        if (row.consumed_at) {
            await trx.updateTable('ai_connections').set({ revoked_at: now }).where('id', '=', row.id).execute();
            return null;
        }
        if (row.refreshExpiry <= now) return null;
        if (scope !== undefined) {
            const requested = scopeSchema.parse(scope.split(' ').filter(Boolean));
            const granted = scopeSchema.parse(JSON.parse(row.scopes));
            if (requested.some(s => !granted.includes(s))) throw new AIError(400, 'invalid_scope');
            // A smaller scope permanently narrows this connection and future refreshes.
            await trx.updateTable('ai_connections').set({ scopes: JSON.stringify(requested) }).where('id', '=', row.id).execute();
        }
        const used = await trx.updateTable('ai_refresh_tokens').set({ consumed_at: now })
            .where('token_hash', '=', row.token_hash).where('consumed_at', 'is', null).executeTakeFirst();
        if (used.numUpdatedRows !== 1n) return null;
        return issueOAuthTokens(trx, row.id, true);
    });
    if (!result) throw new AIError(400, 'invalid_grant');
    return result;
}
