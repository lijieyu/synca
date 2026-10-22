import { afterEach, describe, expect, it, vi } from 'vitest';
import crypto from 'node:crypto';

describe('APNS provider JWT', () => {
    afterEach(() => {
        vi.unstubAllEnvs();
        vi.useRealTimers();
        vi.resetModules();
    });

    it('signs ES256 JWTs as a verifiable 64-byte P1363 signature', async () => {
        // Ephemeral test-only key material; no real APNS credentials or network access.
        const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
        vi.stubEnv('APNS_AUTH_KEY', privateKey.export({ type: 'pkcs8', format: 'pem' }).toString());
        vi.stubEnv('APNS_AUTH_KEY_PATH', '');
        vi.stubEnv('APNS_KEY_ID', 'TESTKEY123');
        vi.stubEnv('APNS_TEAM_ID', 'TESTTEAM12');
        vi.stubEnv('APNS_ENABLED', 'false');
        vi.useFakeTimers();
        vi.setSystemTime(new Date('2026-10-22T12:00:00.000Z'));
        vi.resetModules();

        const { apnsProvider } = await import('../src/apns.js');
        // Inspect the private signer directly, without invoking Apple's push service.
        const token = (apnsProvider as unknown as { ensureJwt(): string }).ensureJwt();
        const [header, claims, encodedSignature] = token.split('.');
        expect(JSON.parse(Buffer.from(header, 'base64url').toString())).toEqual({ alg: 'ES256', kid: 'TESTKEY123' });
        expect(JSON.parse(Buffer.from(claims, 'base64url').toString())).toEqual({ iss: 'TESTTEAM12', iat: 1792670400 });
        const signature = Buffer.from(encodedSignature, 'base64url');
        expect(signature).toHaveLength(64);
        expect(crypto.verify('sha256', Buffer.from(`${header}.${claims}`),
            { key: publicKey, dsaEncoding: 'ieee-p1363' }, signature)).toBe(true);
        expect(crypto.verify('sha256', Buffer.from(`${header}.${claims}tampered`),
            { key: publicKey, dsaEncoding: 'ieee-p1363' }, signature)).toBe(false);
    });
});
