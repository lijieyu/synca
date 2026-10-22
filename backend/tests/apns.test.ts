import { afterEach, describe, expect, it, vi } from 'vitest';
import crypto from 'node:crypto';
import { EventEmitter } from 'node:events';
import http2 from 'node:http2';

vi.mock('../src/store.js', () => ({
    markDevicePushTokenStatus: vi.fn().mockResolvedValue(undefined),
    updateDevicePushTokenEnvironment: vi.fn().mockResolvedValue(undefined),
}));

describe('APNS provider', () => {
    afterEach(() => {
        vi.restoreAllMocks();
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

    async function captureNotification(kind: 'background' | 'alert', badge: number) {
        // Exercise the real request builder with test credentials and an in-memory
        // HTTP/2 peer. Neither Apple's service nor the application DB is contacted.
        const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
        vi.stubEnv('APNS_AUTH_KEY', privateKey.export({ type: 'pkcs8', format: 'pem' }).toString());
        vi.stubEnv('APNS_AUTH_KEY_PATH', '');
        vi.stubEnv('APNS_KEY_ID', 'TESTKEY123');
        vi.stubEnv('APNS_TEAM_ID', 'TESTTEAM12');
        vi.stubEnv('APNS_TOPIC', 'test.synca');
        vi.stubEnv('APNS_ENABLED', 'true');

        const request = Object.assign(new EventEmitter(), {
            setEncoding: vi.fn(),
            end: vi.fn((_body: string) => queueMicrotask(() => {
                request.emit('response', { ':status': 200 });
                request.emit('end');
            })),
        });
        const session = Object.assign(new EventEmitter(), {
            request: vi.fn((_headers: http2.OutgoingHttpHeaders) => request),
            close: vi.fn(),
        });
        vi.spyOn(http2, 'connect').mockReturnValue(session as unknown as http2.ClientHttp2Session);
        const { apnsProvider } = await import('../src/apns.js');
        const result = await apnsProvider.send({
            userId: 'test-user', kind, badge, title: 'Test title', message: 'Test message',
            data: { syncTrigger: true, eventId: 'test-event' },
        }, [{ token: 'a'.repeat(64), apnsEnvironment: 'sandbox' }]);

        expect(result).toEqual({ successCount: 1, failureCount: 0 });
        expect(session.request).toHaveBeenCalledOnce();
        expect(session.close).toHaveBeenCalledOnce();
        return {
            headers: session.request.mock.calls[0][0],
            body: JSON.parse(request.end.mock.calls[0][0]),
        };
    }

    it('sends background sync without alert, sound, or badge even when supplied', async () => {
        const { headers, body } = await captureNotification('background', 5);
        expect(headers).toMatchObject({
            'apns-push-type': 'background', 'apns-priority': '5', 'apns-topic': 'test.synca',
        });
        expect(body).toEqual({
            aps: { 'content-available': 1 }, syncTrigger: true, eventId: 'test-event',
        });
    });

    it.each([0, 5])('preserves alert content and badge %i', async (badge) => {
        const { headers, body } = await captureNotification('alert', badge);
        expect(headers).toMatchObject({ 'apns-push-type': 'alert', 'apns-priority': '10' });
        expect(body).toEqual({
            aps: { alert: { title: 'Test title', body: 'Test message' }, sound: 'default', badge },
            syncTrigger: true, eventId: 'test-event',
        });
    });
});
