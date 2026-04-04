import { v4 as uuidv4 } from 'uuid';
import { getUserByAppleId, createUser, createSession as dbCreateSession, getSession, updateUserEmail } from './store.js';
import { buildAccessStatus, buildTrialWindow } from './access.js';

/**
 * Verify Apple identity token on the server side.
 * Uses apple-signin-auth to validate the JWT against Apple's public keys.
 */
export async function verifyAppleToken(idToken: string): Promise<{
    appleUserId: string;
    email?: string;
}> {
    // Dynamic import to handle ESM/CJS compatibility
    const appleSignin = await import('apple-signin-auth');
    const clientId = process.env.APPLE_CLIENT_ID ?? 'org.haerth.synca';

    const payload = await appleSignin.verifyIdToken(idToken, {
        audience: clientId,
    });

    return {
        appleUserId: payload.sub,
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
}): Promise<{ token: string; user: any; accessStatus: any }> {
    const { appleUserId, email } = await verifyAppleToken(params.idToken);

    const now = new Date();
    const nowIso = now.toISOString();
    let user = await getUserByAppleId(appleUserId);

    if (!user) {
        const trialWindow = buildTrialWindow(now);
        user = await createUser({
            id: uuidv4(),
            appleUserId,
            email,
            nickname: 'Synca 用户',
            now: nowIso,
            trialStartedAt: trialWindow.trialStartedAt,
            trialEndsAt: trialWindow.trialEndsAt,
        });
    } else if (email && user.email !== email) {
        user = (await updateUserEmail(user.id, email, nowIso)) ?? user;
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
