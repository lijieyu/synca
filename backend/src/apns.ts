import crypto from 'node:crypto';
import { logEvent } from './observability.js';
import fs from 'node:fs';
import http2 from 'node:http2';
import { markDevicePushTokenStatus, updateDevicePushTokenEnvironment } from './store.js';

interface PushPayload {
    userId: string;
    title?: string;
    message?: string;
    badge?: number;
    kind?: 'alert' | 'background';
    data?: Record<string, unknown>;
}

type ApnsSendTarget = {
    token: string;
    apnsEnvironment: 'production' | 'sandbox';
    topic?: string;
};

type ApnsSendResult = {
    successCount: number;
    failureCount: number;
};

const APNS_REQUEST_TIMEOUT_MS = 10_000;
const APNS_IDLE_TIMEOUT_MS = 60_000;

type ApnsConfig = {
    enabled: boolean;
    keyId?: string;
    teamId?: string;
    topic?: string;
    privateKey?: string;
};

function base64Url(value: string | Buffer): string {
    return Buffer.from(value)
        .toString('base64')
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');
}

class ApnsProvider {
    private readonly config: ApnsConfig;
    private jwtCache?: { token: string; expiresAtMs: number };

    private sessions = new Map<string, http2.ClientHttp2Session>();
    private idleTimers = new Map<string, NodeJS.Timeout>();

    close() {
        for (const timer of this.idleTimers.values()) clearTimeout(timer);
        this.idleTimers.clear();
        for (const client of this.sessions.values()) client.close();
        this.sessions.clear();
    }

    private retire(host: string, client: http2.ClientHttp2Session) {
        if (this.sessions.get(host) === client) {
            this.sessions.delete(host);
            clearTimeout(this.idleTimers.get(host));
            this.idleTimers.delete(host);
        }
        client.close();
    }

    private session(host: string) {
        let client = this.sessions.get(host);
        if (!client || client.closed || client.destroyed) {
            client = http2.connect(host);
            this.sessions.set(host, client);
            const current = client;
            current.on('error', () => this.retire(host, current));
            current.on('goaway', () => this.retire(host, current));
            current.on('close', () => {
                if (this.sessions.get(host) === current) {
                    this.sessions.delete(host);
                    clearTimeout(this.idleTimers.get(host));
                    this.idleTimers.delete(host);
                }
            });
        }
        clearTimeout(this.idleTimers.get(host));
        const current = client;
        const timer = setTimeout(() => this.retire(host, current), 60_000);
        timer.unref();
        this.idleTimers.set(host, timer);
        return client;
    }

    constructor() {
        this.config = this.loadConfig();
    }

    private loadConfig(): ApnsConfig {
        const enabled = String(process.env.APNS_ENABLED ?? '').toLowerCase() === 'true';
        const keyId = process.env.APNS_KEY_ID?.trim();
        const teamId = process.env.APNS_TEAM_ID?.trim();
        const topic = process.env.APNS_TOPIC?.trim();

        let privateKey = process.env.APNS_AUTH_KEY?.trim();
        const privateKeyPath = process.env.APNS_AUTH_KEY_PATH?.trim();
        if (!privateKey && privateKeyPath) {
            try {
                privateKey = fs.readFileSync(privateKeyPath, 'utf8');
            } catch (error) {
                console.error('[apns] failed to read APNS_AUTH_KEY_PATH:', error);
            }
        }
        if (privateKey) {
            privateKey = privateKey.replace(/\\n/g, '\n');
        }
        return { enabled, keyId, teamId, topic, privateKey };
    }

    private ensureJwt(): string {
        if (!this.config.keyId || !this.config.teamId || !this.config.privateKey) {
            throw new Error('apns_config_missing');
        }
        const nowSec = Math.floor(Date.now() / 1000);
        if (this.jwtCache && nowSec * 1000 < this.jwtCache.expiresAtMs) {
            return this.jwtCache.token;
        }

        const header = base64Url(JSON.stringify({ alg: 'ES256', kid: this.config.keyId }));
        const claims = base64Url(JSON.stringify({ iss: this.config.teamId, iat: nowSec }));
        const unsigned = `${header}.${claims}`;
        const signer = crypto.createSign('sha256');
        signer.update(unsigned);
        signer.end();
        const signature = signer.sign({ key: this.config.privateKey, dsaEncoding: 'ieee-p1363' });
        const jwt = `${unsigned}.${base64Url(signature)}`;
        this.jwtCache = { token: jwt, expiresAtMs: (nowSec + 50 * 60) * 1000 };
        return jwt;
    }

    private isReadyForRealSend(): boolean {
        return Boolean(
            this.config.enabled &&
            this.config.keyId &&
            this.config.teamId &&
            this.config.privateKey &&
            this.config.topic
        );
    }

    async send(payload: PushPayload, targets: ApnsSendTarget[]): Promise<ApnsSendResult> {
        if (targets.length === 0) {
            return { successCount: 0, failureCount: 0 };
        }

        if (!this.config.enabled) {
            logEvent('info', 'apns.dry_run', { kind: payload.kind ?? 'alert', targetCount: targets.length });
            return { successCount: targets.length, failureCount: 0 };
        }

        if (!this.isReadyForRealSend()) {
            throw new Error('APNSConfigMissing');
        }

        let successCount = 0;
        let failureCount = 0;

        for (const target of targets) {
            try {
                try {
                    await this.sendOne(payload, target);
                } catch (error) {
                    const code = (error as NodeJS.ErrnoException).code;
                    // Background sync is idempotent. Alerts may already have been accepted, so do not replay them.
                    if (payload.kind !== 'background' || !['ERR_HTTP2_STREAM_CANCEL', 'ERR_HTTP2_INVALID_SESSION',
                        'ERR_HTTP2_GOAWAY_SESSION', 'ERR_HTTP2_STREAM_ERROR', 'ECONNRESET', 'ETIMEDOUT', 'APNSTimeout', 'APNSConnectionClosed'].includes(code ?? '')) throw error;
                    logEvent('warn', 'apns.retry', { env: target.apnsEnvironment, code });
                    await this.sendOne(payload, target);
                }
                successCount += 1;
                logEvent('info', 'apns.accepted', {
                    env: target.apnsEnvironment,
                    kind: payload.kind ?? 'alert',
                });
                await markDevicePushTokenStatus({
                    token: target.token,
                    isActive: true,
                    lastSentAt: new Date().toISOString(),
                    now: new Date().toISOString(),
                });
            } catch (error) {
                const reason = error instanceof Error ? error.message : 'apns_send_failed';

                // Try fallback environment if BadDeviceToken on production
                if (target.apnsEnvironment === 'production' && reason === 'BadDeviceToken') {
                    try {
                        await this.sendOne(payload, { ...target, apnsEnvironment: 'sandbox' });
                        successCount += 1;
                        const now = new Date().toISOString();
                        await updateDevicePushTokenEnvironment({
                            token: target.token,
                            apnsEnvironment: 'sandbox',
                            now,
                        });
                        await markDevicePushTokenStatus({
                            token: target.token,
                            isActive: true,
                            lastSentAt: now,
                            now,
                        });
                        continue;
                    } catch {
                        // fallback also failed
                    }
                }

                failureCount += 1;
                const deactivate = /Unregistered|BadDeviceToken|DeviceTokenNotForTopic/.test(reason);
                await markDevicePushTokenStatus({
                    token: target.token,
                    isActive: !deactivate,
                    lastError: reason,
                    now: new Date().toISOString(),
                });
                logEvent('error', 'apns.failed', {
                    reason: /^[A-Za-z0-9_]{1,80}$/.test(reason) ? reason : 'transport_error',
                    code: (error as NodeJS.ErrnoException).code,
                    env: target.apnsEnvironment,
                });
            }
        }
        return { successCount, failureCount };
    }

    private async sendOne(payload: PushPayload, target: ApnsSendTarget): Promise<void> {
        const host = target.apnsEnvironment === 'sandbox'
            ? 'https://api.sandbox.push.apple.com'
            : 'https://api.push.apple.com';
        const jwt = this.ensureJwt();
        const client = this.session(host);
        const topic = target.topic?.trim() || this.config.topic!;
        const kind = payload.kind ?? 'alert';
        const body = JSON.stringify({
            aps: {
                ...(kind === 'alert' ? {
                    alert: {
                        title: payload.title ?? 'Synca',
                        body: payload.message ?? '你有新的消息',
                    },
                    sound: 'default',
                    ...(typeof payload.badge === 'number' ? { badge: payload.badge } : {}),
                } : {
                    'content-available': 1,
                }),
            },
            ...(payload.data ?? {}),
        });

        await new Promise<void>((resolve, reject) => {
            let settled = false;
            const closeWith = (fn: () => void, failed = false) => {
                if (settled) return;
                settled = true;
                clearTimeout(timer);
                client.removeListener('error', onSessionError);
                client.removeListener('close', onSessionClose);
                if (failed) this.retire(host, client);
                fn();
            };
            const onSessionError = (err: Error) => closeWith(() => reject(err), true);
            const onSessionClose = () => closeWith(() => reject(Object.assign(new Error('APNSConnectionClosed'), { code: 'APNSConnectionClosed' })), true);
            const timer = setTimeout(() => {
                closeWith(() => reject(Object.assign(new Error('APNSTimeout'), { code: 'APNSTimeout' })), true);
                req.close(http2.constants.NGHTTP2_CANCEL);
            }, APNS_REQUEST_TIMEOUT_MS);
            client.once('error', onSessionError);
            client.once('close', onSessionClose);

            let req: http2.ClientHttp2Stream;
            try { req = client.request({
                ':method': 'POST',
                ':path': `/3/device/${target.token}`,
                'authorization': `bearer ${jwt}`,
                'apns-topic': topic,
                'apns-push-type': kind === 'background' ? 'background' : 'alert',
                'apns-priority': kind === 'background' ? '5' : '10',
            }); } catch (error) { closeWith(() => reject(error), true); return; }

            const chunks: Buffer[] = [];
            let status = 0;

            req.setEncoding('utf8');
            req.on('response', (headers) => {
                status = Number(headers[':status'] ?? 0);
            });
            req.on('data', (chunk) => {
                chunks.push(Buffer.from(chunk));
            });
            req.on('error', (err) => {
                clearTimeout(timer);
                closeWith(() => reject(err), true);
            });
            req.on('close', () => { if (!settled) onSessionClose(); });
            req.on('end', () => {
                clearTimeout(timer);
                const responseText = Buffer.concat(chunks).toString('utf8').trim();
                if (status === 200) {
                    closeWith(() => resolve());
                    return;
                }
                let errorReason = `APNS_${status}`;
                if (responseText) {
                    try {
                        const parsed = JSON.parse(responseText) as { reason?: string };
                        if (parsed.reason) errorReason = parsed.reason;
                    } catch {
                        // Never log an untrusted upstream body. Keep the status code.
                    }
                }
                closeWith(() => reject(new Error(errorReason)));
            });

            req.end(body);
        });
    }
}

export const apnsProvider = new ApnsProvider();
