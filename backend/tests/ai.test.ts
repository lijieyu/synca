import fs from 'node:fs/promises';
import path from 'node:path';
import { describe, it, expect, beforeAll, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { randomUUID, createHash } from 'node:crypto';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import app from '../src/app.js';
import { db } from '../src/db.js';
import { runMigrations } from '../src/migrate.js';
import { resetDb, createSession, createUser } from '../src/store.js';
import { connection, cleanupAIState, hash } from '../src/aiCore.js';
import type { Server } from 'node:http';

let userId: string, session: string, token: string, connectionId: string;
const auth = () => `Bearer ${token}`;
const call = (name: string, args: unknown = {}, credential = token) => request(app).post(`/api/ai/tools/${name}`).set('Authorization', `Bearer ${credential}`).send(args);
async function record(text = 'hello Synca') {
    const made = await call('create_record', { textContent: text, idempotencyKey: randomUUID() });
    expect(made.status).toBe(200);
    return (await call('read_record', { id: made.body.id })).body;
}
if (!process.env.DB_PATH?.includes('test')) throw new Error('AI tests require an isolated test DB_PATH');
beforeAll(runMigrations);
afterEach(async () => {
    const files = await db.selectFrom('messages').select(['image_path', 'file_path']).where('user_id', '=', userId).execute();
    for (const file of files) for (const [folder, name] of [['uploads', file.image_path], ['files', file.file_path]]) {
        if (name && path.basename(name) === name) await fs.unlink(path.resolve(folder!, name)).catch(() => {});
    }
});
beforeEach(async () => {
    await resetDb();
    userId = randomUUID(); session = randomUUID();
    await createUser({ id: userId, appleUserId: userId, nickname: 'AI test', now: new Date().toISOString() });
    await createSession(session, userId);
    const c = await connection(userId, 'test AI', ['read', 'create', 'update', 'delete', 'attachments'], 30);
    token = c.token; connectionId = c.id;
});
describe('AI authorization and content contract', () => {
    it('hashes tokens, isolates sessions, defaults web token to explicit permissions, and revokes immediately', async () => {
        const row = await db.selectFrom('ai_connections').selectAll().where('id', '=', connectionId).executeTakeFirstOrThrow();
        expect(row.token_hash).not.toBe(token);
        expect((await request(app).delete('/me/account').set('Authorization', auth())).status).toBe(403);
        expect((await request(app).post('/api/ai/connections').set('Authorization', auth()).send({ name: 'escalate', scopes: ['delete'] })).status).toBe(401);
        expect((await request(app).post('/api/ai/tools/get_usage').set('Authorization', `Bearer ${session}`).send({})).status).toBe(401);
        expect((await request(app).delete(`/api/ai/connections/${connectionId}`).set('Authorization', `Bearer ${session}`)).status).toBe(200);
        expect((await call('get_usage')).status).toBe(401);
    });
    it('enforces scope on tools and attachment routes even for admin accounts', async () => {
        const read = await connection(userId, 'reader', ['read'], 30);
        expect((await call('create_record', { textContent: 'x', idempotencyKey: randomUUID() }, read.token)).status).toBe(403);
        expect((await request(app).post('/messages/image').set('Authorization', `Bearer ${read.token}`)).status).toBe(403);
        expect((await call('manage_category', { action: 'create', name: 'x', idempotencyKey: randomUUID() }, read.token)).status).toBe(403);
    });
    it('supports real MCP initialize, discovery and calls with the official client', async () => {
        const server: Server = await new Promise(resolve => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
        const address = server.address() as { port: number };
        const client = new Client({ name: 'integration-test', version: '1' });
        try {
            await client.connect(new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${address.port}/mcp`), { requestInit: { headers: { Authorization: auth() } } }));
            const tools = await client.listTools();
            expect(tools.tools.map(t => t.name)).toContain('update_records');
            const result = await client.callTool({ name: 'create_record', arguments: { textContent: 'MCP actual call', idempotencyKey: randomUUID() } });
            expect(result.isError).not.toBe(true);
            const listing = await client.callTool({ name: 'search_records', arguments: { query: 'MCP' } });
            expect(JSON.stringify(listing)).toContain('MCP actual call');
        } finally { await client.close(); await new Promise<void>(resolve => server.close(() => resolve())); }
    });
    it('retries text creation without duplication, rejects key reuse and retains existing client limits', async () => {
        const args = { textContent: 'once', idempotencyKey: randomUUID() };
        const a = await call('create_record', args); const b = await call('create_record', args);
        expect(a.body.id).toBe(b.body.id);
        expect((await call('create_record', { ...args, textContent: 'different' })).status).toBe(409);
        expect((await call('search_records')).body.messages).toHaveLength(1);
        expect((await call('create_record', { ...args, idempotencyKey: randomUUID(), textContent: 'x'.repeat(2001) })).status).toBe(400);
        for (let n = 1; n < 20; n++) expect((await call('create_record', { textContent: 'quota', idempotencyKey: randomUUID() })).status).toBe(200);
        expect((await call('create_record', { textContent: 'over quota', idempotencyKey: randomUUID() })).body.error).toBe('daily_limit_reached');
    });
    it('prevents cross-account reads, writes, category assignment and confirmations', async () => {
        const m = await record();
        const otherId = randomUUID();
        await createUser({ id: otherId, appleUserId: otherId, nickname: 'Other', now: new Date().toISOString() });
        const other = await connection(otherId, 'other', ['read', 'update', 'delete'], 30);
        expect((await call('search_records', {}, other.token)).body.messages).toHaveLength(0);
        expect((await call('read_record', { id: m.id }, other.token)).status).toBe(404);
        expect((await call('update_records', { items: [{ id: m.id, expectedUpdatedAt: m.updatedAt }], isCleared: true }, other.token)).status).toBe(404);
        expect((await call('prepare_delete_records', { items: [{ id: m.id, expectedUpdatedAt: m.updatedAt }] }, other.token)).status).toBe(404);
        const cats = await call('list_categories', {}, other.token);
        expect((await call('update_records', { items: [{ id: m.id, expectedUpdatedAt: m.updatedAt }], categoryId: cats.body[0].id })).status).toBe(404);
    });
    it('keeps usage, categories and operation results scoped to the token owner', async () => {
        const m = await record();
        await db.updateTable('users').set({ lifetime_purchased_at: new Date().toISOString() }).where('id', '=', userId).execute();
        const usage = await call('get_usage');
        expect(usage.body.access.isUnlimited).toBe(true);
        expect(usage.body.access.todayLimit).toBeNull();
        expect(usage.body.unclearedCount).toBe(1);
        const otherId = randomUUID();
        await createUser({ id: otherId, appleUserId: otherId, nickname: 'Other', now: new Date().toISOString() });
        const other = await connection(otherId, 'Other', ['read', 'delete', 'update'], 30);
        const otherUsage = await call('get_usage', {}, other.token);
        expect(otherUsage.body.unclearedCount).toBe(0);
        expect(otherUsage.body.access.isUnlimited).toBe(false);
        const ownCategories = (await call('list_categories')).body;
        const foreignCategories = (await call('list_categories', {}, other.token)).body;
        expect(foreignCategories.some((c: { id: string }) => ownCategories.some((own: { id: string }) => own.id === c.id))).toBe(false);
        const op = await db.selectFrom('ai_operations').select('id').where('user_id', '=', userId).executeTakeFirstOrThrow();
        expect((await call('get_operation', { id: op.id }, other.token)).status).toBe(404);
        expect((await call('read_record', { id: m.id, userId }, other.token)).status).toBe(400);
    });
    it('serializes concurrent retries and rejects invalid category creation without leaking a default record', async () => {
        const args = { textContent: 'Concurrent', idempotencyKey: randomUUID() };
        const results = await Promise.all([call('create_record', args), call('create_record', args)]);
        expect(results.map(r => r.status)).toEqual([200, 200]);
        expect(results[0].body.id).toBe(results[1].body.id);
        expect((await call('create_record', { textContent: 'wrong category', categoryId: randomUUID(), idempotencyKey: randomUUID() })).status).toBe(404);
        expect((await call('search_records')).body.messages).toHaveLength(1);
    });
    it('expires confirmation previews and removes their text without deleting records', async () => {
        const m = await record('private preview');
        const prepared = await call('prepare_delete_records', { items: [{ id: m.id, expectedUpdatedAt: m.updatedAt }] });
        await db.updateTable('ai_operations').set({ expires_at: '2000-01-01T00:00:00.000Z' }).where('id', '=', prepared.body.operationId).execute();
        await cleanupAIState();
        const op = await db.selectFrom('ai_operations').selectAll().where('id', '=', prepared.body.operationId).executeTakeFirstOrThrow();
        expect(op.status).toBe('expired'); expect(op.payload).not.toContain('private preview');
        expect((await call('read_record', { id: m.id })).status).toBe(200);
        expect((await request(app).post(`/api/ai/confirmations/${op.id}`).set('Authorization', `Bearer ${session}`).send({ approve: true })).status).toBe(410);
    });
    it('paginates deterministic ties, escapes LIKE and rejects invalid cursors', async () => {
        const a = await record('100% idea'); await record('100x idea'); await record('中文灵感');
        const first = await call('search_records', { limit: 2 });
        const second = await call('search_records', { limit: 2, cursor: first.body.nextCursor });
        expect(first.body.messages.length + second.body.messages.length).toBe(3);
        expect(new Set([...first.body.messages, ...second.body.messages].map(m => m.id)).size).toBe(3);
        expect((await call('search_records', { query: '%' })).body.messages.map((m: { id: string }) => m.id)).toEqual([a.id]);
        expect((await call('search_records', { cursor: 'bad' })).status).toBe(400);
    });
    it('edits and restores records through the unchanged legacy incremental-sync contract; batches roll back on conflict', async () => {
        const a = await record('original'); const b = await record('second');
        const edit = await call('update_records', { items: [{ id: a.id, expectedUpdatedAt: a.updatedAt }], textContent: 'edited', isCleared: true });
        expect(edit.status).toBe(200);
        const legacy = await request(app).get(`/messages?since=${encodeURIComponent(a.updatedAt)}`).set('Authorization', `Bearer ${session}`);
        expect(legacy.body.messages.find((m: { id: string }) => m.id === a.id)).toMatchObject({ textContent: 'edited', isCleared: true });
        const conflict = await call('update_records', { items: [{ id: b.id, expectedUpdatedAt: b.updatedAt }, { id: a.id, expectedUpdatedAt: a.updatedAt }], isCleared: true });
        expect(conflict.status).toBe(409);
        expect((await call('read_record', { id: b.id })).body.isCleared).toBe(false);
        expect((await call('update_records', { items: [{ id: a.id, expectedUpdatedAt: edit.body.items[0].updatedAt }], isCleared: false })).status).toBe(200);
        expect((await call('read_record', { id: a.id })).body.isCleared).toBe(false);
    });
    it('keeps category deletion compatible: records move to Default, duplicate creation retries do not duplicate categories', async () => {
        const args = { action: 'create', name: 'Work', color: 'sky', idempotencyKey: randomUUID() };
        const category = await call('manage_category', args);
        expect((await call('manage_category', args)).body.id).toBe(category.body.id);
        const m = await record();
        expect((await call('update_records', { items: [{ id: m.id, expectedUpdatedAt: m.updatedAt }], categoryId: category.body.id })).status).toBe(200);
        expect((await call('manage_category', { action: 'delete', id: category.body.id, expectedUpdatedAt: category.body.updatedAt, idempotencyKey: randomUUID() })).status).toBe(200);
        expect((await call('read_record', { id: m.id })).body.categoryIsDefault).toBe(true);
    });
    it('requires a human session for deletion and binds the exact preview, version, connection and expiry', async () => {
        const m = await record();
        const prepare = await call('prepare_delete_records', { items: [{ id: m.id, expectedUpdatedAt: m.updatedAt }] });
        expect(prepare.body.count).toBe(1);
        const path = `/api/ai/confirmations/${prepare.body.operationId}`;
        expect((await request(app).post(path).set('Authorization', auth()).send({ approve: true })).status).toBe(401);
        expect((await call('read_record', { id: m.id })).status).toBe(200);
        expect((await request(app).post(path).set('Authorization', `Bearer ${session}`).send({ approve: true })).body.deletedCount).toBe(1);
        expect((await request(app).post(path).set('Authorization', `Bearer ${session}`).send({ approve: true })).body.deletedCount).toBe(1);
        expect((await call('read_record', { id: m.id })).status).toBe(404);
        const legacy = await request(app).get(`/messages?since=${encodeURIComponent(m.updatedAt)}`).set('Authorization', `Bearer ${session}`);
        expect(legacy.body.messages.find((x: { id: string }) => x.id === m.id).isDeleted).toBe(true);
    });
    it('refuses deletion if a previewed record changed or the connection was revoked', async () => {
        const m = await record();
        const prepared = await call('prepare_delete_records', { items: [{ id: m.id, expectedUpdatedAt: m.updatedAt }] });
        await call('update_records', { items: [{ id: m.id, expectedUpdatedAt: m.updatedAt }], textContent: 'newer' });
        expect((await request(app).post(`/api/ai/confirmations/${prepared.body.operationId}`).set('Authorization', `Bearer ${session}`).send({ approve: true })).status).toBe(409);
        await request(app).delete(`/api/ai/connections/${connectionId}`).set('Authorization', `Bearer ${session}`);
        expect((await request(app).post(`/api/ai/confirmations/${prepared.body.operationId}`).set('Authorization', `Bearer ${session}`).send({ approve: true })).status).toBe(403);
    });
    it('uploads inline images and files idempotently and applies the existing paid-file policy', async () => {
        const args = { kind: 'image', fileName: 'pixel.png', mimeType: 'image/png', idempotencyKey: randomUUID(),
            base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=' };
        const image = await call('create_attachment', args);
        expect(image.status).toBe(200);
        expect((await call('create_attachment', args)).body.id).toBe(image.body.id);
        const read = await call('read_attachment', { recordId: image.body.id });
        expect(read.body.attachment.data).toBe(args.base64);
        const file = { kind: 'file', fileName: 'notes.md', mimeType: 'text/markdown', idempotencyKey: randomUUID(), base64: Buffer.from('Test note').toString('base64') };
        expect((await call('create_attachment', file)).status).toBe(403);
        await db.updateTable('users').set({ lifetime_purchased_at: new Date().toISOString() }).where('id', '=', userId).execute();
        const created = await call('create_attachment', file);
        expect(created.status).toBe(200);
        expect((await call('read_attachment', { recordId: created.body.id })).body.attachment.mimeType).toBe('text/markdown');
        expect((await call('create_attachment', { ...file, base64: '!!!!', idempotencyKey: randomUUID() })).status).toBe(400);
    });
    it('handles attachment transfer metadata and denies foreign media even when AI account is admin', async () => {
        const instructions = await call('attachment_transfer', { action: 'upload_image' });
        expect(instructions.body.url).toBe('https://synca.haerth.cn/messages/image');
        expect(instructions.body.limits.imageLimitBytes).toBeGreaterThan(0);
        const image = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=', 'base64');
        const uploaded = await request(app).post('/messages/image').set('Authorization', auth()).set('X-Upload-ID', randomUUID()).set('X-Upload-Size', String(image.length))
            .attach('image', image, { filename: 'pixel.png', contentType: 'image/png' });
        expect(uploaded.status).toBe(201);
        const transfer = await call('attachment_transfer', { action: 'download', recordId: uploaded.body.id });
        expect(transfer.body.url).toContain('/api/media/');
        expect((await request(app).get(new URL(transfer.body.url).pathname).set('Authorization', auth())).status).toBe(200);
        const foreignId = randomUUID();
        await createUser({ id: foreignId, appleUserId: foreignId, nickname: 'Admin', now: new Date().toISOString() });
        await db.updateTable('users').set({ is_admin: 1 }).where('id', '=', foreignId).execute();
        const admin = await connection(foreignId, 'admin AI', ['read', 'attachments'], 30);
        expect((await request(app).get(new URL(transfer.body.url).pathname).set('Authorization', `Bearer ${admin.token}`)).status).toBe(403);
        await db.updateTable('messages').set({ attachment_expires_at: '2000-01-01T00:00:00.000Z' }).where('id', '=', uploaded.body.id).execute();
        expect((await call('attachment_transfer', { action: 'download', recordId: uploaded.body.id })).status).toBe(410);
    });
});
describe('MCP OAuth consent and PKCE', () => {
    it('advertises resource metadata, rejects cross-origin calls and wrong redirects', async () => {
        const metadata = await request(app).get('/.well-known/oauth-protected-resource/mcp');
        expect(metadata.body.resource).toBe('https://synca.haerth.cn/mcp');
        expect((await request(app).post('/mcp').set('Origin', 'https://evil.example').set('Authorization', auth()).send({})).status).toBe(403);
        expect((await request(app).post('/mcp').send({})).headers['www-authenticate']).toContain('oauth-protected-resource/mcp');
        expect((await request(app).post('/oauth/register').send({ redirect_uris: ['http://evil.example/callback'] })).status).toBe(400);
    });
    it('advertises implemented auth methods and rejects unsupported or unsafe registration', async () => {
        const metadata = await request(app).get('/.well-known/oauth-authorization-server');
        expect(metadata.body.token_endpoint_auth_methods_supported).toEqual(['none', 'client_secret_post', 'client_secret_basic']);
        expect(metadata.body.grant_types_supported).toEqual(['authorization_code', 'refresh_token']);
        for (const extra of [{ grant_types: ['refresh_token'] }, { grant_types: ['client_credentials'] },
            { token_endpoint_auth_method: 'private_key_jwt' }, { response_types: [] },
            { redirect_uris: ['https://user:password@client.example/callback'] }, { redirect_uris: ['https://client.example/callback#fragment'] }]) {
            expect((await request(app).post('/oauth/register').send({ redirect_uris: ['https://client.example/callback'], ...extra })).status).toBe(400);
        }
    });
    it.each(['none', 'client_secret_post', 'client_secret_basic'])('negotiates refresh requests and completes PKCE with %s', async method => {
        const redirect = 'http://127.0.0.1:34567/callback';
        const registration = await request(app).post('/oauth/register').send({ client_name: 'Compatibility test', redirect_uris: [redirect],
            grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'], token_endpoint_auth_method: method });
        expect(registration.status, JSON.stringify(registration.body)).toBe(201);
        expect(registration.body.grant_types).toEqual(['authorization_code', 'refresh_token']);
        expect(registration.body.token_endpoint_auth_method).toBe(method);
        const { client_id, client_secret } = registration.body;
        const stored = await db.selectFrom('ai_oauth_clients').selectAll().where('id', '=', client_id).executeTakeFirstOrThrow();
        if (method === 'none') expect(client_secret).toBeUndefined();
        else { expect(client_secret.length).toBeGreaterThan(30); expect(stored.metadata).not.toContain(client_secret); }
        const verifier = 'z'.repeat(43);
        const start = await request(app).get('/oauth/authorize').query({ client_id, redirect_uri: redirect,
            response_type: 'code', code_challenge_method: 'S256', code_challenge: createHash('sha256').update(verifier).digest('base64url'), scope: 'read' });
        expect(start.status).toBe(302);
        const id = new URL(start.headers.location, 'https://synca.haerth.cn').searchParams.get('authorize');
        const consent = await request(app).post(`/api/ai/authorization/${id}`).set('Authorization', `Bearer ${session}`).send({ approve: true });
        const code = new URL(consent.body.redirectUrl).searchParams.get('code');
        const args = { grant_type: 'authorization_code', code, code_verifier: verifier, redirect_uri: redirect };
        if (method !== 'none') {
            expect((await request(app).post('/oauth/token').type('form').send({ ...args, client_id })).status).toBe(401);
            expect((await request(app).post('/oauth/token').type('form').send({ ...args, client_id, client_secret: 'wrong' })).status).toBe(401);
        }
        if (method === 'client_secret_basic') {
            expect((await request(app).post('/oauth/token').type('form').send({ ...args, client_id, client_secret })).status).toBe(401);
            expect((await request(app).post('/oauth/token').set('Authorization', `Basic ${Buffer.from(`${client_id}:${client_secret}`).toString('base64')}`).type('form').send({ ...args, client_id, client_secret })).status).toBe(401);
        }
        const exchange = () => {
            let r = request(app).post('/oauth/token').type('form');
            if (method === 'client_secret_basic') r = r.set('Authorization', `Basic ${Buffer.from(`${client_id}:${client_secret}`).toString('base64')}`);
            return r.send({ ...args, ...(method === 'client_secret_basic' ? {} : { client_id }), ...(method === 'client_secret_post' ? { client_secret } : {}) });
        };
        const result = await exchange();
        expect(result.status, JSON.stringify(result.body)).toBe(200);
        expect((await call('get_usage', {}, result.body.access_token)).status).toBe(200);
        expect(result.body.expires_in).toBe(3600);
        expect(result.body.refresh_token).toMatch(/^synca_refresh_/);
        let refreshRequest = request(app).post('/oauth/token').type('form');
        if (method === 'client_secret_basic') refreshRequest = refreshRequest.set('Authorization', `Basic ${Buffer.from(`${client_id}:${client_secret}`).toString('base64')}`);
        const rotated = await refreshRequest.send({ grant_type: 'refresh_token', refresh_token: result.body.refresh_token,
            ...(method === 'client_secret_basic' ? {} : { client_id }), ...(method === 'client_secret_post' ? { client_secret } : {}) });
        expect(rotated.status).toBe(200);
        expect(rotated.body.refresh_token).not.toBe(result.body.refresh_token);
        result.body.access_token = rotated.body.access_token;
        expect((await call('create_record', { textContent: 'no write permission', idempotencyKey: randomUUID() }, result.body.access_token)).status).toBe(403);
        expect((await exchange()).status).toBe(400);
        const connections = await request(app).get('/api/ai/connections').set('Authorization', `Bearer ${session}`);
        expect(JSON.stringify(connections.body)).not.toContain(client_secret ?? 'client_secret_hash');
        const linked = connections.body.connections.find((c: { name: string }) => c.name === 'Compatibility test');
        await request(app).delete(`/api/ai/connections/${linked.id}`).set('Authorization', `Bearer ${session}`);
        expect((await call('get_usage', {}, result.body.access_token)).status).toBe(401);
    });
    async function renewable() {
        const reg = await request(app).post('/oauth/register').send({ redirect_uris: ['https://client.example/callback'], grant_types: ['authorization_code', 'refresh_token'] });
        const clientId = reg.body.client_id;
        const verifier = 'r'.repeat(43);
        const start = await request(app).get('/oauth/authorize').query({ client_id: clientId, redirect_uri: 'https://client.example/callback',
            response_type: 'code', code_challenge_method: 'S256', code_challenge: createHash('sha256').update(verifier).digest('base64url'), scope: 'read create' });
        const id = new URL(start.headers.location, 'https://synca.haerth.cn').searchParams.get('authorize');
        expect((await request(app).get(`/api/ai/authorization/${id}`)).status).toBe(401);
        expect((await request(app).post(`/api/ai/authorization/${id}`).send({ approve: true })).status).toBe(401);
        expect((await request(app).post(`/api/ai/authorization/${id}`).set('Authorization', auth()).send({ approve: true })).status).toBe(401);
        const consent = await request(app).post(`/api/ai/authorization/${id}`).set('Authorization', `Bearer ${session}`).send({ approve: true });
        const exchanged = await request(app).post('/oauth/token').type('form').send({ grant_type: 'authorization_code', client_id: clientId,
            code: new URL(consent.body.redirectUrl).searchParams.get('code'), code_verifier: verifier, redirect_uri: 'https://client.example/callback' });
        expect(exchanged.status).toBe(200);
        const row = await db.selectFrom('ai_connections').selectAll().where('token_hash', '=', hash(exchanged.body.access_token)).executeTakeFirstOrThrow();
        expect(Math.round((Date.parse(row.expires_at) - Date.parse(row.created_at)) / 86400000)).toBe(365);
        return { clientId, row, tokens: exchanged.body };
    }
    const renew = (clientId: string, refresh_token: string, extra = {}) => request(app).post('/oauth/token').type('form')
        .send({ grant_type: 'refresh_token', client_id: clientId, refresh_token, ...extra });
    it('refreshes expired access, binds client/resource/scope, and revokes the family on replay', async () => {
        const { clientId, row, tokens } = await renewable();
        const other = await request(app).post('/oauth/register').send({ redirect_uris: ['https://other.example/callback'], grant_types: ['authorization_code', 'refresh_token'] });
        expect((await renew(other.body.client_id, tokens.refresh_token)).status).toBe(400);
        expect((await renew(clientId, tokens.refresh_token, { resource: 'https://evil.example' })).status).toBe(400);
        expect((await renew(clientId, tokens.refresh_token, { scope: 'read delete' })).status).toBe(400);
        await db.updateTable('ai_connections').set({ access_expires_at: '2000-01-01T00:00:00.000Z' }).where('id', '=', row.id).execute();
        expect((await call('get_usage', {}, tokens.access_token)).status).toBe(401);
        const next = await renew(clientId, tokens.refresh_token, { scope: 'read' });
        expect(next.status).toBe(200);
        expect(next.body.scope).toBe('read');
        expect((await call('get_usage', {}, next.body.access_token)).status).toBe(200);
        expect((await renew(clientId, next.body.refresh_token, { scope: 'create' })).status).toBe(400);
        const stored = await db.selectFrom('ai_refresh_tokens').selectAll().where('connection_id', '=', row.id).execute();
        expect(JSON.stringify(stored)).not.toContain(tokens.refresh_token);
        expect((await renew(clientId, tokens.refresh_token)).status).toBe(400);
        expect((await call('get_usage', {}, next.body.access_token)).status).toBe(401);
        expect((await renew(clientId, next.body.refresh_token)).status).toBe(400);
    });
    it.each(['idle', 'grant', 'revoked'])('rejects refresh after %s expiry or revocation', async reason => {
        const { clientId, row, tokens } = await renewable();
        if (reason === 'idle') await db.updateTable('ai_refresh_tokens').set({ expires_at: '2000-01-01T00:00:00.000Z' }).where('connection_id', '=', row.id).execute();
        else await db.updateTable('ai_connections').set(reason === 'grant' ? { expires_at: '2000-01-01T00:00:00.000Z' } : { revoked_at: new Date().toISOString() }).where('id', '=', row.id).execute();
        expect((await renew(clientId, tokens.refresh_token)).status).toBe(400);
    });
    it('does not extend the one-year grant and detects concurrent refresh reuse', async () => {
        const { clientId, row, tokens } = await renewable();
        const end = new Date(Date.now() + 90000).toISOString();
        await db.updateTable('ai_connections').set({ expires_at: end }).where('id', '=', row.id).execute();
        const results = await Promise.all([renew(clientId, tokens.refresh_token), renew(clientId, tokens.refresh_token)]);
        expect(results.map(r => r.status).sort()).toEqual([200, 400]);
        const winner = results.find(r => r.status === 200)!;
        expect(winner.body.expires_in).toBeLessThanOrEqual(90);
        expect((await call('get_usage', {}, winner.body.access_token)).status).toBe(401);
        const latest = await db.selectFrom('ai_connections').selectAll().where('id', '=', row.id).executeTakeFirstOrThrow();
        expect(latest.expires_at).toBe(end);
    });
    it('keeps legacy tokens valid through additive migrations and excludes deleted records from counts', async () => {
        await runMigrations(); await runMigrations();
        const made = await record();
        expect((await call('get_usage')).body.unclearedCount).toBe(1);
        await db.updateTable('messages').set({ is_deleted: 1 }).where('id', '=', made.id).execute();
        expect((await call('get_usage')).body.unclearedCount).toBe(0);
    });
    it('binds authorization code to consent, client, redirect URI, resource and one-use PKCE exchange', async () => {
        const registration = await request(app).post('/oauth/register').send({ client_name: 'Client', redirect_uris: ['https://client.example/callback'] });
        expect(registration.status).toBe(201);
        const client_id = registration.body.client_id;
        const verifier = 'a'.repeat(43);
        const query = { client_id, redirect_uri: 'https://client.example/callback', response_type: 'code', code_challenge_method: 'S256',
            code_challenge: createHash('sha256').update(verifier).digest('base64url'), scope: 'read create', state: 'original-state', resource: 'https://synca.haerth.cn/mcp' };
        expect((await request(app).get('/oauth/authorize').query({ ...query, redirect_uri: 'https://evil.example' })).status).toBe(400);
        const start = await request(app).get('/oauth/authorize').query(query);
        expect(start.status).toBe(302);
        const id = new URL(start.headers.location, 'https://synca.haerth.cn').searchParams.get('authorize');
        expect((await request(app).get(`/api/ai/authorization/${id}`).set('Authorization', `Bearer ${session}`)).body.scopes).toEqual(['read', 'create']);
        const consent = await request(app).post(`/api/ai/authorization/${id}`).set('Authorization', `Bearer ${session}`).send({ approve: true });
        const callback = new URL(consent.body.redirectUrl);
        expect(callback.searchParams.get('state')).toBe('original-state');
        const args = { client_id, redirect_uri: query.redirect_uri, grant_type: 'authorization_code', code: callback.searchParams.get('code'), code_verifier: verifier, resource: query.resource };
        expect((await request(app).post('/oauth/token').type('form').send({ ...args, code_verifier: 'b'.repeat(43) })).status).toBe(400);
        expect((await request(app).post('/oauth/token').type('form').send({ ...args, resource: 'https://evil.example' })).status).toBe(400);
        const exchanged = await request(app).post('/oauth/token').type('form').send(args);
        expect(exchanged.status).toBe(200);
        expect((await call('get_usage', {}, exchanged.body.access_token)).status).toBe(200);
        expect((await request(app).post('/oauth/token').type('form').send(args)).status).toBe(400);
    });
});
