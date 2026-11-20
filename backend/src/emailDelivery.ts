import { createHmac, randomUUID } from 'node:crypto';

const REQUEST_TIMEOUT_MS = 10_000;
// Current endpoint table and official dm-20151123 SDK use this version in all
// regions. Legacy public-parameters documentation still mentions 2017-06-22.
// https://help.aliyun.com/zh/direct-mail/api-endpoints
const API_VERSION = '2015-11-23';
const ENDPOINTS: Readonly<Record<string, string>> = Object.freeze({
    'cn-hangzhou': 'https://dm.aliyuncs.com/',
    'ap-southeast-1': 'https://dm.ap-southeast-1.aliyuncs.com/',
    'ap-southeast-2': 'https://dm.ap-southeast-2.aliyuncs.com/',
    'us-east-1': 'https://dm.us-east-1.aliyuncs.com/',
    'eu-central-1': 'https://dm.eu-central-1.aliyuncs.com/',
});

type VerificationEmail = { email: string; code: string; locale?: string };

function isSingleMailbox(value: string): boolean {
    return value.length <= 254 && /^[^\s@,;<>:]+@[^\s@,;<>:]+\.[^\s@,;<>:]+$/.test(value);
}

function getConfiguration() {
    const accessKeyId = process.env.ALIYUN_DM_ACCESS_KEY_ID?.trim();
    const accessKeySecret = process.env.ALIYUN_DM_ACCESS_KEY_SECRET?.trim();
    const accountName = process.env.ALIYUN_DM_ACCOUNT_NAME?.trim();
    const region = process.env.ALIYUN_DM_REGION?.trim() || 'cn-hangzhou';
    const securityToken = process.env.ALIYUN_DM_SECURITY_TOKEN?.trim();
    if (!accessKeyId || !accessKeySecret || !accountName || !isSingleMailbox(accountName)
        || !Object.hasOwn(ENDPOINTS, region)) return null;
    return { accessKeyId, accessKeySecret, accountName, region, securityToken, endpoint: ENDPOINTS[region] };
}

export function isEmailDeliveryConfigured(): boolean {
    return getConfiguration() !== null;
}

function percentEncode(value: string): string {
    return encodeURIComponent(value).replace(/[!'()*]/g, char => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
}

function canonicalQuery(parameters: Readonly<Record<string, string>>): string {
    return Object.keys(parameters).sort().map(key => `${percentEncode(key)}=${percentEncode(parameters[key])}`).join('&');
}

// RPC signature v1: RFC 3986 encoding, then HMAC-SHA1 with the trailing '&'.
// https://www.alibabacloud.com/help/en/direct-mail/signature
export function signDirectMailRequest(parameters: Readonly<Record<string, string>>, secret: string): string {
    const unsigned = Object.fromEntries(Object.entries(parameters).filter(([key]) => key !== 'Signature'));
    const stringToSign = `POST&%2F&${percentEncode(canonicalQuery(unsigned))}`;
    return createHmac('sha1', `${secret}&`).update(stringToSign).digest('base64');
}

function emailContent(code: string, locale = 'en'): { Subject: string; TextBody: string } {
    if (/^zh(?:-|$)/i.test(locale)) {
        if (/^zh-(?:hant|tw|hk|mo)(?:-|$)/i.test(locale)) {
            return {
                Subject: 'Synca 登入驗證碼',
                TextBody: `你的 Synca 登入驗證碼是：${code}\n\n驗證碼在 10 分鐘內有效，請勿向他人透露。\n如果你沒有請求登入，請忽略這封郵件。`,
            };
        }
        return {
            Subject: 'Synca 登录验证码',
            TextBody: `你的 Synca 登录验证码是：${code}\n\n验证码在 10 分钟内有效，请勿向他人透露。\n如果你没有请求登录，请忽略这封邮件。`,
        };
    }
    return {
        Subject: 'Your Synca sign-in code',
        TextBody: `Your Synca sign-in code is: ${code}\n\nThis code expires in 10 minutes. Do not share it with anyone.\nIf you did not request this code, you can ignore this email.`,
    };
}

export async function sendVerificationEmail({ email, code, locale }: VerificationEmail): Promise<void> {
    const config = getConfiguration();
    if (!config || !isSingleMailbox(email) || !/^\d{6}$/.test(code)) {
        throw new Error('email_delivery_failed');
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    timeout.unref();
    try {
        const parameters: Record<string, string> = {
            Action: 'SingleSendMail', Format: 'JSON', Version: API_VERSION,
            AccessKeyId: config.accessKeyId, RegionId: config.region,
            SignatureMethod: 'HMAC-SHA1', SignatureVersion: '1.0',
            SignatureNonce: randomUUID(), Timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
            AccountName: config.accountName, AddressType: '1', ReplyToAddress: 'false',
            FromAlias: 'Synca', ToAddress: email, ...emailContent(code, locale),
        };
        if (config.securityToken) parameters.SecurityToken = config.securityToken;
        parameters.Signature = signDirectMailRequest(parameters, config.accessKeySecret);
        const response = await fetch(config.endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: canonicalQuery(parameters),
            signal: controller.signal,
            // Never forward signed credentials or email contents to a redirect.
            redirect: 'error',
        });
        if (!response.ok) {
            await response.body?.cancel();
            throw new Error('email_delivery_failed');
        }
        const result: unknown = await response.json();
        if (!result || typeof result !== 'object' || 'Code' in result
            || !('RequestId' in result) || typeof result.RequestId !== 'string' || !result.RequestId.trim()) {
            throw new Error('email_delivery_failed');
        }
    } catch {
        // Provider/network errors can contain the address, message or signed
        // request. Keep both message and cause free of provider-controlled data.
        // Do not retry: a timeout may still have resulted in an accepted email.
        throw new Error('email_delivery_failed');
    } finally {
        clearTimeout(timeout);
    }
}
