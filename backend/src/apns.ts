import crypto from 'node:crypto';
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
        const signature = signer.sign(this.config.privateKey);
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
            console.log('[push:dry]', JSON.stringify({
                payload: { ...payload, kind: payload.kind ?? 'alert' },
                targets: targets.map((t) => ({ token: `${t.token.slice(0, 8)}...`, env: t.apnsEnvironment })),
            }));
            return { successCount: targets.length, failureCount: 0 };
        }

        if (!this.isReadyForRealSend()) {
            throw new Error('APNSConfigMissing');
        }

        let successCount = 0;
        let failureCount = 0;

        for (const target of targets) {
            try {
                await this.sendOne(payload, target);
                successCount += 1;
                console.log('[apns] send ok', {
                    token: `${target.token.slice(0, 8)}...`,
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
                console.error('[apns] send failed', {
                    reason,
                    token: `${target.token.slice(0, 8)}...`,
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
        const client = http2.connect(host);

        const jwt = this.ensureJwt();
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
                } : {
                    'content-available': 1,
                }),
                ...(typeof payload.badge === 'number' ? { badge: payload.badge } : {}),
            },
            ...(payload.data ?? {}),
        });

        await new Promise<void>((resolve, reject) => {
            let settled = false;
            const closeWith = (fn: () => void) => {
                if (settled) return;
                settled = true;
                try { fn(); } finally { client.close(); }
            };
            const timer = setTimeout(() => {
                closeWith(() => reject(new Error('APNSTimeout')));
            }, 10_000);

            client.on('error', (err) => {
                clearTimeout(timer);
                closeWith(() => reject(err));
            });

            const req = client.request({
                ':method': 'POST',
                ':path': `/3/device/${target.token}`,
                'authorization': `bearer ${jwt}`,
                'apns-topic': topic,
                'apns-push-type': kind === 'background' ? 'background' : 'alert',
                'apns-priority': kind === 'background' ? '5' : '10',
            });

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
                closeWith(() => reject(err));
            });
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
                        errorReason = `${errorReason}:${responseText}`;
                    }
                }
                closeWith(() => reject(new Error(errorReason)));
            });

            req.end(body);
        });
    }
}

export const apnsProvider = new ApnsProvider();
