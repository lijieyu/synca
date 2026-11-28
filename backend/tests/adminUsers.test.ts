import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { sql } from 'kysely';
import { randomUUID } from 'node:crypto';
import app from '../src/app.js';
import { db } from '../src/db.js';
import { runMigrations } from '../src/migrate.js';
import { createSession, createUser, resetDb } from '../src/store.js';

async function account(apple: boolean, emailLogin: boolean) {
    const id = randomUUID(), token = randomUUID(), now = new Date().toISOString();
    // Profile email alone must not imply verified email login.
    await createUser({ id, appleUserId: apple ? randomUUID() : null, email: `${id}@example.com`, nickname: 'Synca 用户', now });
    if (emailLogin) await sql`INSERT INTO email_identities(email,user_id,created_at) VALUES(${`${id}@example.com`},${id},${now})`.execute(db);
    await createSession(token, id);
    return { id, token };
}

describe('admin user login methods', () => {
    beforeAll(runMigrations);
    beforeEach(resetDb);

    it('reports verified Apple, email and linked identities without exposing Apple identifiers', async () => {
        const apple = await account(true, false);
        const email = await account(false, true);
        const linked = await account(true, true);
        await db.updateTable('users').set({ is_admin: 1 }).where('id', '=', apple.id).execute();
        const response = await request(app).get('/api/admin/users').set('Authorization', `Bearer ${apple.token}`).expect(200);
        for (const [user, methods] of [[apple, ['apple']], [email, ['email']], [linked, ['apple', 'email']]] as const) {
            const result = response.body.users.find((row: { id: string }) => row.id === user.id);
            expect(result.loginMethods).toEqual(methods);
            expect(result).not.toHaveProperty('apple_user_id');
        }
    });

    it('keeps user identities restricted to admins', async () => {
        const user = await account(false, true);
        await request(app).get('/api/admin/users').expect(401);
        await request(app).get('/api/admin/users').set('Authorization', `Bearer ${user.token}`).expect(403);
    });
});
