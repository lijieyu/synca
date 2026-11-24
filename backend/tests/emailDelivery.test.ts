import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { isEmailDeliveryConfigured, sendVerificationEmail, signDirectMailRequest } from '../src/emailDelivery.js';

const message = { email: 'person+login@example.com', code: '582691', locale: 'en' };
const fetchMock = vi.fn<typeof fetch>();

describe('Aliyun DirectMail delivery', () => {
    beforeEach(() => {
        vi.stubEnv('ALIYUN_DM_ACCESS_KEY_ID', 'testid');
        vi.stubEnv('ALIYUN_DM_ACCESS_KEY_SECRET', 'testsecret');
        vi.stubEnv('ALIYUN_DM_ACCOUNT_NAME', 'login@example.com');
        vi.stubEnv('ALIYUN_DM_REGION', '');
        vi.stubEnv('ALIYUN_DM_SECURITY_TOKEN', '');
        vi.stubGlobal('fetch', fetchMock);
        vi.spyOn(console, 'info').mockImplementation(() => {});
        fetchMock.mockResolvedValue(new Response(JSON.stringify({ RequestId: 'test-request', EnvId: 'test-envelope' })));
    });

    afterEach(() => {
        vi.unstubAllEnvs();
        vi.unstubAllGlobals();
        vi.restoreAllMocks();
        vi.useRealTimers();
        fetchMock.mockReset();
    });

    it('matches the official POST signature vector including apostrophe and percent encoding', () => {
        // https://www.alibabacloud.com/help/en/direct-mail/signature
        const parameters = Object.fromEntries(new URLSearchParams(
            "AccessKeyId=testid&AccountName=%3Ca%25b'%3E&Action=SingleSendMail&AddressType=1&Format=XML&HtmlBody=4&RegionId=cn-hangzhou&ReplyToAddress=true&SignatureMethod=HMAC-SHA1&SignatureNonce=c1b2c332-4cfb-4a0f-b8cc-ebe622aa0a5c&SignatureVersion=1.0&Subject=3&TagName=2&Timestamp=2016-10-20T06:27:56Z&ToAddress=1@test.com&Version=2015-11-23",
        ));
        expect(signDirectMailRequest(parameters, 'testsecret')).toBe('llJfXJjBW3OacrVgxxsITgYaYm0=');
        expect(signDirectMailRequest({ ...parameters, Signature: 'previous' }, 'testsecret')).toBe('llJfXJjBW3OacrVgxxsITgYaYm0=');
    });

    it('POSTs a signed single-recipient transactional email without exposing credentials in the URL', async () => {
        expect(isEmailDeliveryConfigured()).toBe(true);
        await expect(sendVerificationEmail(message)).resolves.toBeUndefined();
        expect(fetchMock).toHaveBeenCalledOnce();
        const [url, init] = fetchMock.mock.calls[0];
        expect(url).toBe('https://dm.aliyuncs.com/');
        expect(init).toMatchObject({ method: 'POST', redirect: 'error', headers: { 'Content-Type': 'application/x-www-form-urlencoded' } });
        const body = new URLSearchParams(String(init?.body));
        expect(Object.fromEntries(body)).toMatchObject({
            Action: 'SingleSendMail', Version: '2015-11-23', RegionId: 'cn-hangzhou',
            AccountName: 'login@example.com', AddressType: '1', ReplyToAddress: 'false',
            ToAddress: message.email, Format: 'JSON', FromAlias: 'Synca',
            SignatureMethod: 'HMAC-SHA1', SignatureVersion: '1.0', AccessKeyId: 'testid',
        });
        expect(body.get('TextBody')).toContain(message.code);
        expect(body.get('TextBody')).toContain('10 minutes');
        expect(body.get('Subject')).toContain('Synca');
        expect(body.get('Signature')).toMatch(/^[A-Za-z0-9+/]{27}=$/);
        expect(body.get('SignatureNonce')).toMatch(/^[a-f0-9-]{36}$/);
        expect(body.get('Timestamp')).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
        expect(String(init?.body)).not.toContain('testsecret');
        expect(body.has('SecurityToken')).toBe(false);
    });

    it('records provider acceptance identifiers without logging recipient, code, credentials or response contents', async () => {
        fetchMock.mockResolvedValueOnce(new Response(JSON.stringify({
            RequestId: '2D086F6B-8F31-4658-84C1-006DED334ACD',
            EnvId: '600000373230455440',
            Message: `${message.email} ${message.code} testsecret`,
        })));
        await sendVerificationEmail(message);
        expect(console.info).toHaveBeenCalledExactlyOnceWith('[email/delivery]', JSON.stringify({
            status: 'provider_accepted',
            requestId: '2D086F6B-8F31-4658-84C1-006DED334ACD',
            envelopeId: '600000373230455440',
        }));
    });

    it('omits unexpected identifier contents without turning an accepted email into a failed send', async () => {
        fetchMock.mockResolvedValueOnce(new Response(JSON.stringify({
            RequestId: `${message.email}\n${message.code}`,
            EnvId: { code: message.code, secret: 'testsecret' },
        })));
        await expect(sendVerificationEmail(message)).resolves.toBeUndefined();
        expect(console.info).toHaveBeenCalledExactlyOnceWith('[email/delivery]', JSON.stringify({
            status: 'provider_accepted',
        }));
    });

    it.each([
        ['ap-southeast-1', 'https://dm.ap-southeast-1.aliyuncs.com/'],
        ['ap-southeast-2', 'https://dm.ap-southeast-2.aliyuncs.com/'],
        ['us-east-1', 'https://dm.us-east-1.aliyuncs.com/'],
        ['eu-central-1', 'https://dm.eu-central-1.aliyuncs.com/'],
    ])('uses the documented endpoint and API version for %s', async (region, endpoint) => {
        vi.stubEnv('ALIYUN_DM_REGION', region);
        vi.stubEnv('ALIYUN_DM_SECURITY_TOKEN', 'test-sts-token');
        await sendVerificationEmail(message);
        const [url, init] = fetchMock.mock.calls[0];
        expect(url).toBe(endpoint);
        const body = new URLSearchParams(String(init?.body));
        expect(body.get('Version')).toBe('2015-11-23');
        expect(body.get('RegionId')).toBe(region);
        expect(body.get('SecurityToken')).toBe('test-sts-token');
    });

    it.each([
        ['ALIYUN_DM_ACCESS_KEY_ID', ''], ['ALIYUN_DM_ACCESS_KEY_SECRET', '  '],
        ['ALIYUN_DM_ACCOUNT_NAME', ''], ['ALIYUN_DM_ACCOUNT_NAME', 'a@example.com,b@example.com'],
        ['ALIYUN_DM_REGION', 'https://untrusted.example'], ['ALIYUN_DM_REGION', '__proto__'],
    ])('fails closed before network access for invalid configuration %s=%s', async (key, value) => {
        vi.stubEnv(key, value);
        expect(isEmailDeliveryConfigured()).toBe(false);
        await expect(sendVerificationEmail(message)).rejects.toThrow('email_delivery_failed');
        expect(fetchMock).not.toHaveBeenCalled();
    });

    it.each([['zh', '验证码'], ['zh-Hant', '驗證碼'], ['zh-TW', '驗證碼']])('localizes the message for %s', async (locale, label) => {
        await sendVerificationEmail({ ...message, locale });
        const body = new URLSearchParams(String(fetchMock.mock.calls[0][1]?.body));
        expect(body.get('TextBody')).toContain(label);
        expect(body.get('TextBody')).toContain(message.code);
        expect(body.get('TextBody')).toContain('10');
    });

    it.each([
        { email: 'one@example.com,two@example.com' }, { email: 'one@example.com\r\nBcc:two@example.com' },
        { code: '12345' }, { code: '123456\n' },
    ])('rejects invalid verification input before sending: %j', async (invalid) => {
        await expect(sendVerificationEmail({ ...message, ...invalid })).rejects.toThrow('email_delivery_failed');
        expect(fetchMock).not.toHaveBeenCalled();
    });

    it.each([
        [400, { RequestId: 'test-request', Code: 'InvalidToAddress', Message: 'sensitive recipient/code' }],
        [200, { RequestId: 'test-request', Code: 'InvalidSendMail.Spam', Message: 'sensitive recipient/code' }],
        [200, {}], [200, null], [200, { RequestId: '' }],
    ])('rejects failed or malformed provider responses (%s) with a sanitized error', async (status, result) => {
        fetchMock.mockResolvedValueOnce(new Response(JSON.stringify(result), { status }));
        const error = await sendVerificationEmail(message).catch(error => error);
        expect(error).toBeInstanceOf(Error);
        expect(error.message).toBe('email_delivery_failed');
        expect(error.cause).toBeUndefined();
        expect(fetchMock).toHaveBeenCalledOnce();
        expect(console.info).not.toHaveBeenCalled();
    });

    it('sanitizes non-JSON and network failures without automatic retries', async () => {
        fetchMock.mockResolvedValueOnce(new Response('sensitive malformed response'));
        await expect(sendVerificationEmail(message)).rejects.toThrow('email_delivery_failed');
        fetchMock.mockRejectedValueOnce(new Error('sensitive credentials in network failure'));
        const error = await sendVerificationEmail(message).catch(error => error);
        expect(error.message).toBe('email_delivery_failed');
        expect(error.cause).toBeUndefined();
        expect(fetchMock).toHaveBeenCalledTimes(2);
    });

    it('aborts a stalled request after ten seconds and clears its timer', async () => {
        vi.useFakeTimers();
        fetchMock.mockImplementationOnce((_url, init) => new Promise((_resolve, reject) => {
            init?.signal?.addEventListener('abort', () => reject(new Error('sensitive timeout')), { once: true });
        }));
        const result = sendVerificationEmail(message).catch(error => error);
        await vi.advanceTimersByTimeAsync(10_000);
        expect(await result).toMatchObject({ message: 'email_delivery_failed' });
        expect(fetchMock.mock.calls[0][1]?.signal?.aborted).toBe(true);
        expect(vi.getTimerCount()).toBe(0);
        expect(console.info).not.toHaveBeenCalled();
    });
});
