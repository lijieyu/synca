import { createHash, createHmac, randomBytes, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import { sql, type Kysely } from 'kysely';
import { db } from './db.js';
import type { Database } from './db_types.js';
import { getUser } from './store.js';
import { buildAccessStatus } from './access.js';
import { verifyAppleToken } from './auth.js';
import { isEmailDeliveryConfigured, sendVerificationEmail } from './emailDelivery.js';

const CODE_LIFETIME = 10 * 60_000;
const RESEND_DELAY = 60_000;
const HOUR = 3_600_000;
export class LoginError extends Error {
    constructor(readonly code: string, readonly status = 400, readonly retryAfter?: number) { super(code); }
}
export interface BindingActor { userId: string; sessionToken: string }
export interface LoginMethods { apple: boolean; email: string | null }
interface EmailChallenge {
    id: string; email: string; purpose: string; user_id: string | null; session_hash: string | null;
    code_hash: string; expires_at: number; resend_at: number; attempts: number; status: string;
}
const hash = (s: string) => createHash('sha256').update(s).digest('hex');
function secret() {
    const key = process.env.EMAIL_AUTH_SECRET?.trim();
    if (!key || Buffer.byteLength(key) < 32) throw new LoginError('email_unavailable', 503);
    return key;
}
function digest(id: string, code: string) { return createHmac('sha256', secret()).update(`${id}:${code}`).digest('hex'); }
export function normalizeLoginEmail(value: string) {
    const email = value.trim().toLowerCase();
    // One ASCII mailbox only. Preserve dots/plus aliases; never infer providers or merge identities.
    if (email.length > 254 || !/^[a-z0-9.!#$%&'*+\-/=?^_`{|}~]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/i.test(email) || email.split('@')[0].length > 64 || email.startsWith('.') || email.includes('..') || email.includes('.@')) throw new LoginError('invalid_email');
    return email;
}
async function rateLimit(trx: Kysely<Database>, scope: string, key: string, limit: number, duration: number, now: number) {
    const bucket = `${scope}:${hash(key)}:${Math.floor(now / duration)}`;
    const end = (Math.floor(now / duration) + 1) * duration;
    const { rows } = await sql<{ count: number }>`INSERT INTO auth_rate_limits(bucket,count,expires_at) VALUES(${bucket},1,${end})
        ON CONFLICT(bucket) DO UPDATE SET count=count+1 RETURNING count`.execute(trx);
    if (rows[0].count > limit) throw new LoginError('rate_limited', 429, Math.max(1, Math.ceil((end - now) / 1000)));
}
async function cleanup(trx: Kysely<Database>, now: number) {
    await sql`DELETE FROM auth_rate_limits WHERE expires_at<${now}`.execute(trx);
    await sql`DELETE FROM email_auth_challenges WHERE expires_at<${now - 86_400_000}`.execute(trx);
    await sql`DELETE FROM apple_binding_challenges WHERE expires_at<${now - 86_400_000}`.execute(trx);
}
export async function getLoginMethods(userId: string, executor: Kysely<Database> = db): Promise<LoginMethods> {
    const user = await executor.selectFrom('users').select('apple_user_id').where('id', '=', userId).executeTakeFirst();
    if (!user) throw new LoginError('unauthorized', 401);
    const { rows } = await sql<{ email: string }>`SELECT email FROM email_identities WHERE user_id=${userId}`.execute(executor);
    return { apple: Boolean(user.apple_user_id), email: rows[0]?.email ?? null };
}
export async function requestEmailCode(input: { email: string; locale?: string; ip: string; actor?: BindingActor }) {
    const email = normalizeLoginEmail(input.email);
    secret();
    if (!isEmailDeliveryConfigured()) throw new LoginError('email_unavailable', 503);
    const now = Date.now(), id = randomBytes(32).toString('hex'), code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const purpose = input.actor ? 'bind' : 'login', userId = input.actor?.userId ?? null;
    const sessionHash = input.actor ? hash(input.actor.sessionToken) : null;
    await db.transaction().execute(async trx => {
        await rateLimit(trx, 'email-send-ip', input.ip, 20, HOUR, now);
        await rateLimit(trx, 'email-send-address', email, 5, HOUR, now);
        await rateLimit(trx, 'email-send-global-hour', 'global', 200, HOUR, now);
        await rateLimit(trx, 'email-send-global-day', 'global', 1000, 24 * HOUR, now);
        if (input.actor) {
            const session = await trx.selectFrom('sessions').select('user_id').where('token','=',input.actor.sessionToken).executeTakeFirst();
            if (session?.user_id !== userId) throw new LoginError('unauthorized',401);
            const methods = await getLoginMethods(userId!, trx);
            if (methods.email) throw new LoginError('email_already_bound', 409);
        }
        const recent = (await sql<{ resend_at: number }>`SELECT resend_at FROM email_auth_challenges WHERE email=${email}
            AND status IN ('pending','sent') AND resend_at>${now} ORDER BY resend_at DESC LIMIT 1`.execute(trx)).rows[0];
        if (recent) throw new LoginError('rate_limited', 429, Math.ceil((recent.resend_at - now) / 1000));
        await cleanup(trx, now);
        await sql`INSERT INTO email_auth_challenges(id,email,purpose,user_id,session_hash,code_hash,created_at,expires_at,resend_at,status)
            VALUES(${id},${email},${purpose},${userId},${sessionHash},${digest(id,code)},${now},${now+CODE_LIFETIME},${now+RESEND_DELAY},'pending')`.execute(trx);
    });
    try { await sendVerificationEmail({ email, code, locale: input.locale }); }
    catch {
        await sql`UPDATE email_auth_challenges SET status='failed' WHERE id=${id}`.execute(db);
        throw new LoginError('email_send_failed', 503);
    }
    await db.transaction().execute(async trx => {
        // Failed sends do not invalidate an earlier working code. Only the newest
        // accepted send becomes active, atomically with invalidating older proofs.
        await sql`UPDATE email_auth_challenges SET status='superseded' WHERE email=${email} AND purpose=${purpose}
            AND user_id IS ${userId} AND id<>${id} AND status='sent'`.execute(trx);
        await sql`UPDATE email_auth_challenges SET status='sent' WHERE id=${id} AND status='pending'`.execute(trx);
    });
    return { challengeId: id, expiresAt: new Date(now+CODE_LIFETIME).toISOString(), resendAt: new Date(now+RESEND_DELAY).toISOString() };
}
export async function verifyEmailCode(input: { challengeId: string; code: string; ip: string; actor?: BindingActor; deviceId?: string }) {
    const now = Date.now(), purpose = input.actor ? 'bind' : 'login';
    const result = await db.transaction().execute(async trx => {
        await rateLimit(trx, 'email-verify-ip', input.ip, 60, HOUR, now);
        if (input.actor) {
            const session = await trx.selectFrom('sessions').select('user_id').where('token','=',input.actor.sessionToken).executeTakeFirst();
            if (session?.user_id !== input.actor.userId) return new LoginError('unauthorized',401);
        }
        const proof = (await sql<EmailChallenge>`SELECT * FROM email_auth_challenges WHERE id=${input.challengeId} AND purpose=${purpose}
            AND user_id IS ${input.actor?.userId ?? null} AND session_hash IS ${input.actor ? hash(input.actor.sessionToken) : null}`.execute(trx)).rows[0];
        if (!proof || proof.status !== 'sent') return new LoginError('invalid_code');
        if (proof.attempts >= 5) return new LoginError('code_attempts_exceeded');
        if (proof.expires_at <= now) return new LoginError('code_expired');
        await sql`UPDATE email_auth_challenges SET attempts=attempts+1 WHERE id=${proof.id}`.execute(trx);
        const given = Buffer.from(digest(proof.id,input.code),'hex'), expected = Buffer.from(proof.code_hash,'hex');
        if (given.length !== expected.length || !timingSafeEqual(given, expected)) return new LoginError('invalid_code');
        const identity = (await sql<{ user_id: string }>`SELECT user_id FROM email_identities WHERE email=${proof.email}`.execute(trx)).rows[0];
        await sql`UPDATE email_auth_challenges SET status='consumed' WHERE id=${proof.id}`.execute(trx);
        if (input.actor) {
            const methods = await getLoginMethods(input.actor.userId, trx);
            if (methods.email) return new LoginError('email_already_bound',409);
            if (identity && identity.user_id !== input.actor.userId) return new LoginError('email_in_use',409);
            await sql`INSERT INTO email_identities(email,user_id,created_at) VALUES(${proof.email},${input.actor.userId},${new Date(now).toISOString()})`.execute(trx);
            await trx.updateTable('users').set({ email: proof.email, updated_at: new Date(now).toISOString() }).where('id','=',input.actor.userId).execute();
            return { methods: await getLoginMethods(input.actor.userId,trx) };
        }
        const userId = identity?.user_id ?? randomUUID(), time = new Date(now).toISOString();
        if (!identity) {
            await trx.insertInto('users').values({id:userId,apple_user_id:null,email:proof.email,nickname:'Synca 用户',
                trial_started_at:null,trial_ends_at:null,purchase_date:null,subscription_expires_at:null,lifetime_purchased_at:null,
                store_product_id:null,is_admin:0,created_at:time,updated_at:time}).execute();
            await sql`INSERT INTO email_identities(email,user_id,created_at) VALUES(${proof.email},${userId},${time})`.execute(trx);
        }
        const token = randomUUID();
        await trx.insertInto('sessions').values({token,user_id:userId,device_id:input.deviceId ?? null,created_at:time}).execute();
        return { token, userId };
    });
    // Return errors rather than throwing inside the transaction so failed attempts
    // and consumed proofs are durably committed.
    if (result instanceof LoginError) throw result;
    if ('methods' in result) return result.methods;
    return { token: result.token, user: await getUser(result.userId), accessStatus: await buildAccessStatus(result.userId,new Date(now)) };
}
export async function requestAppleBinding(actor: BindingActor) {
    const now = Date.now();
    return db.transaction().execute(async trx => {
        // Reopening settings must not generate proofs or consume a shared office
        // IP quota. Reuse this session's proof until shortly before expiry.
        await cleanup(trx,now);
        const existing = (await sql<{id:string;nonce:string;expires_at:number}>`SELECT id,nonce,expires_at FROM apple_binding_challenges
            WHERE user_id=${actor.userId} AND session_hash=${hash(actor.sessionToken)} AND consumed=0 AND expires_at>${now+120_000}
            ORDER BY expires_at DESC LIMIT 1`.execute(trx)).rows[0];
        if (existing) return {challengeId:existing.id,nonce:existing.nonce,expiresAt:new Date(existing.expires_at).toISOString()};
        await rateLimit(trx,'apple-bind-user',actor.userId,30,HOUR,now);
        const challengeId=randomBytes(32).toString('hex'),nonce=randomBytes(32).toString('hex'),expiresAt=now+CODE_LIFETIME;
        await sql`INSERT INTO apple_binding_challenges(id,user_id,session_hash,nonce,expires_at)
            VALUES(${challengeId},${actor.userId},${hash(actor.sessionToken)},${nonce},${expiresAt})`.execute(trx);
        return {challengeId,nonce,expiresAt:new Date(expiresAt).toISOString()};
    });
}
export async function bindAppleIdentity(actor: BindingActor, input: { challengeId: string; idToken: string }, ip: string) {
    const now = Date.now();
    await db.transaction().execute(trx=>rateLimit(trx,'apple-bind-verify-ip',ip,30,HOUR,now));
    const proof = (await sql<{nonce:string}>`SELECT nonce FROM apple_binding_challenges WHERE id=${input.challengeId} AND user_id=${actor.userId}
        AND session_hash=${hash(actor.sessionToken)} AND consumed=0 AND expires_at>${now}`.execute(db)).rows[0];
    if (!proof) throw new LoginError('invalid_code');
    let apple;
    try { apple = await verifyAppleToken(input.idToken); } catch { throw new LoginError('apple_auth_failed'); }
    if (!apple.nonce || apple.nonce !== proof.nonce) throw new LoginError('apple_auth_failed');
    const result = await db.transaction().execute(async trx => {
        const consumed = await sql`UPDATE apple_binding_challenges SET consumed=1 WHERE id=${input.challengeId} AND consumed=0
            AND expires_at>${Date.now()} RETURNING id`.execute(trx);
        if (!consumed.rows.length) return new LoginError('invalid_code');
        const session=await trx.selectFrom('sessions').select('user_id').where('token','=',actor.sessionToken).executeTakeFirst();
        if (session?.user_id !== actor.userId) return new LoginError('unauthorized',401);
        const methods=await getLoginMethods(actor.userId,trx);
        if (methods.apple) return new LoginError('apple_already_bound',409);
        const owner=await trx.selectFrom('users').select('id').where('apple_user_id','=',apple.appleUserId).executeTakeFirst();
        if (owner && owner.id!==actor.userId) return new LoginError('apple_in_use',409);
        await trx.updateTable('users').set({apple_user_id:apple.appleUserId,updated_at:new Date().toISOString()}).where('id','=',actor.userId).execute();
        return await getLoginMethods(actor.userId,trx);
    });
    if (result instanceof LoginError) throw result;
    return result;
}
