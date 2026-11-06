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
        expect(session.close).not.toHaveBeenCalled();
        apnsProvider.close();
        return {
            headers: session.request.mock.calls[0][0],
            body: JSON.parse(request.end.mock.calls[0][0]),
        };
    }

    it.each([true, false])('reuses connections and retries transient cancellation only for background=%s', async (background) => {
        await captureNotification('background', 0);
        vi.restoreAllMocks();
        vi.resetModules();
        const sessions: any[] = [];
        let attempts = 0;
        vi.spyOn(http2, 'connect').mockImplementation(() => {
            const peer = Object.assign(new EventEmitter(), {
                close: vi.fn(), destroy: vi.fn(), unref: vi.fn(),
                request: vi.fn(() => {
                    const req = Object.assign(new EventEmitter(), { setEncoding: vi.fn(), close: vi.fn(),
                        end: vi.fn(() => queueMicrotask(() => {
                            attempts++;
                            if (attempts === 1) req.emit('error', Object.assign(new Error('stream canceled'), { code: 'ERR_HTTP2_STREAM_CANCEL' }));
                            else { req.emit('response', { ':status': 200 }); req.emit('end'); }
                        })) });
                    return req;
                }),
            });
            sessions.push(peer);
            return peer as unknown as http2.ClientHttp2Session;
        });
        const { apnsProvider } = await import('../src/apns.js');
        const result = await apnsProvider.send({ userId: 'test', kind: background ? 'background' : 'alert' },
            [{ token: 'b'.repeat(64), apnsEnvironment: 'production' }]);
        expect(result).toEqual(background ? { successCount: 1, failureCount: 0 } : { successCount: 0, failureCount: 1 });
        expect(attempts).toBe(background ? 2 : 1);
        if (background) {
            await apnsProvider.send({ userId: 'test', kind: 'background' }, [{ token: 'c'.repeat(64), apnsEnvironment: 'production' }]);
            expect(sessions).toHaveLength(2); // first failed connection replaced; successful connection reused
        }
        (apnsProvider as any).close();
    });

    it.each(['transient', 'permanent', 'timeout', 'goaway'])('bounds retries and cleans up %s connections', async (failure) => {
        await captureNotification('background', 0);
        vi.restoreAllMocks(); vi.resetModules(); vi.useFakeTimers();
        const peers: any[] = [];
        vi.spyOn(http2, 'connect').mockImplementation(() => {
            const peer = Object.assign(new EventEmitter(), { close: vi.fn(), destroy: vi.fn(), request: vi.fn(() => {
                const req = Object.assign(new EventEmitter(), { setEncoding: vi.fn(), close: vi.fn(), end: vi.fn(() => {
                    if (failure === 'timeout') return;
                    queueMicrotask(() => {
                        if (failure === 'transient') req.emit('error', Object.assign(new Error('cancelled'), { code: 'ERR_HTTP2_STREAM_CANCEL' }));
                        else {
                            if (failure === 'goaway') peer.emit('goaway');
                            req.emit('response', { ':status': failure === 'permanent' ? 400 : 200 });
                            if (failure === 'permanent') req.emit('data', '{"reason":"BadDeviceToken"}');
                            req.emit('end');
                        }
                    });
                }) }); return req;
            }) }); peers.push(peer); return peer as unknown as http2.ClientHttp2Session;
        });
        const { apnsProvider } = await import('../src/apns.js');
        const payload = { userId: 'test', kind: 'background' as const };
        const targets = [{ token: 'd'.repeat(64), apnsEnvironment: 'sandbox' as const }];
        const pending = apnsProvider.send(payload, targets);
        if (failure === 'timeout') await vi.advanceTimersByTimeAsync(20001);
        const result = await pending;
        expect(result).toEqual({ successCount: failure === 'goaway' ? 1 : 0, failureCount: failure === 'goaway' ? 0 : 1 });
        expect(peers).toHaveLength(['transient', 'timeout'].includes(failure) ? 2 : 1);
        expect(peers.every(peer => peer.destroy.mock.calls.length === 0)).toBe(true);
        if (failure === 'goaway') { await apnsProvider.send(payload, targets); expect(peers).toHaveLength(2); }
        apnsProvider.close();
        expect(vi.getTimerCount()).toBe(0);
    });

    it('lets an in-flight alert finish when a background stream on the shared session times out', async () => {
        await captureNotification('background', 0);
        vi.restoreAllMocks(); vi.resetModules(); vi.useFakeTimers();
        const peers: any[] = [];
        vi.spyOn(http2, 'connect').mockImplementation(() => {
            const streams: EventEmitter[] = [];
            const peer = Object.assign(new EventEmitter(), { close: vi.fn(),
                destroy: vi.fn(() => streams.forEach(req => req.emit('error', new Error('destroyed')))),
                request: vi.fn((headers) => {
                    const req = Object.assign(new EventEmitter(), { setEncoding: vi.fn(), close: vi.fn(),
                        end: vi.fn(() => {
                            if (headers['apns-push-type'] === 'alert') setTimeout(() => {
                                req.emit('response', { ':status': 200 }); req.emit('end');
                            }, 7000);
                        }) }); streams.push(req); return req;
                }),
            }); peers.push(peer); return peer as unknown as http2.ClientHttp2Session;
        });
        const { apnsProvider } = await import('../src/apns.js');
        const targets = [{ token: 'e'.repeat(64), apnsEnvironment: 'production' as const }];
        const background = apnsProvider.send({ userId: 'test', kind: 'background' }, targets);
        await vi.advanceTimersByTimeAsync(5000);
        const alert = apnsProvider.send({ userId: 'test', kind: 'alert' }, targets);
        await vi.advanceTimersByTimeAsync(7000);
        expect(await alert).toEqual({ successCount: 1, failureCount: 0 });
        expect(peers[0].request).toHaveBeenCalledTimes(2);
        expect(peers[0].destroy).not.toHaveBeenCalled();
        await vi.advanceTimersByTimeAsync(8001);
        expect(await background).toEqual({ successCount: 0, failureCount: 1 });
        apnsProvider.close();
    });

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
