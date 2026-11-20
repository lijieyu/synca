import { v4 as uuidv4 } from 'uuid';
import { getUserByAppleId, createUser, createSession as dbCreateSession, getSession, getUser, updateUserNickname } from './store.js';
import { buildAccessStatus } from './access.js';
import { sql } from 'kysely';
import { db } from './db.js';

/**
 * Verify Apple identity token on the server side.
 * Uses apple-signin-auth to validate the JWT against Apple's public keys.
 */
export async function verifyAppleToken(idToken: string): Promise<{
    appleUserId: string;
    email?: string;
    nonce?: string;
}> {
    // Dynamic import to handle ESM/CJS compatibility
    const appleSignin = await import('apple-signin-auth');
    const clientId = process.env.APPLE_CLIENT_ID ?? 'org.haerth.synca';
    const webClientId = process.env.APPLE_WEB_CLIENT_ID ?? 'cn.haerth.synca.web';

    const payload = await appleSignin.verifyIdToken(idToken, {
        audience: [clientId, webClientId],
    });

    if (typeof payload.sub !== 'string' || !payload.sub) throw new Error('invalid_apple_subject');
    return {
        appleUserId: payload.sub,
        nonce: typeof payload.nonce === 'string' ? payload.nonce : undefined,
        email: payload.email,
    };
}

/**
 * Login or register a user via Apple Sign In.
 * Returns a session token and user info.
 */
export async function loginWithApple(params: {
    idToken: string;
    deviceId?: string;
    name?: string;
}): Promise<{ token: string; user: any; accessStatus: any }> {
    const { appleUserId, email } = await verifyAppleToken(params.idToken);

    const now = new Date();
    const nowIso = now.toISOString();
    let user = await getUserByAppleId(appleUserId);

    if (!user) {
        try { user = await createUser({
            id: uuidv4(),
            appleUserId,
            email,
            nickname: params.name?.trim() || 'Synca 用户',
            now: nowIso,
            trialStartedAt: null,
            trialEndsAt: null,
        }); } catch (error) {
            // Concurrent Apple sign-ins resolve to the unique existing identity.
            user = await getUserByAppleId(appleUserId);
            if (!user) throw error;
        }
    } else {
        if (email && user.email !== email) {
            // One atomic statement: an email binding that won the race must not
            // be overwritten by an earlier Apple profile response.
            await sql`UPDATE users SET email=${email},updated_at=${nowIso} WHERE id=${user.id}
                AND NOT EXISTS(SELECT 1 FROM email_identities WHERE user_id=${user.id})`.execute(db);
            user = (await getUser(user.id)) ?? user;
        }
        if (params.name && params.name.trim().length > 0 && user.nickname === 'Synca 用户') {
            user = (await updateUserNickname(user.id, params.name.trim(), nowIso)) ?? user;
        }
    }

    const token = uuidv4();
    await dbCreateSession(token, user.id, params.deviceId);
    const accessStatus = await buildAccessStatus(user.id, now);

    return { token, user, accessStatus };
}

/**
 * Extract user ID from Bearer token.
 */
export async function getUserIdFromToken(rawAuth?: string): Promise<string | null> {
    if (!rawAuth?.startsWith('Bearer ')) return null;
    const token = rawAuth.slice('Bearer '.length).trim();
    const userId = await getSession(token);
    return userId ?? null;
}
