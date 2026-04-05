import fs from 'fs';
import path from 'path';
import { Environment, JWSTransactionDecodedPayload, SignedDataVerifier } from '@apple/app-store-server-library';

export const MONTHLY_PRODUCT_ID = 'org.haerth.synca.unlimited.monthly';
export const YEARLY_PRODUCT_ID = 'org.haerth.synca.unlimited.yearly';
export const LIFETIME_PRODUCT_ID = 'org.haerth.synca.unlimited.lifetime';
export const SUPPORTED_PRODUCT_IDS = new Set([MONTHLY_PRODUCT_ID, YEARLY_PRODUCT_ID, LIFETIME_PRODUCT_ID]);
export const MONTHLY_TO_LIFETIME_DISCOUNT_LABEL = process.env.LIFETIME_UPGRADE_MONTHLY_PRICE_LABEL ?? '¥78';
export const YEARLY_TO_LIFETIME_DISCOUNT_LABEL = process.env.LIFETIME_UPGRADE_YEARLY_PRICE_LABEL ?? '¥58';

const bundleId = process.env.APPLE_CLIENT_ID ?? 'org.haerth.synca';
const appleAppId = process.env.APP_STORE_APPLE_ID ? Number(process.env.APP_STORE_APPLE_ID) : undefined;
const appleRootCAs = loadAppleRootCAs();
const verifierCache = new Map<Environment, SignedDataVerifier>();

export function isSupportedProduct(productId: string | null | undefined): productId is string {
    return Boolean(productId && SUPPORTED_PRODUCT_IDS.has(productId));
}

export function isLifetimeProduct(productId: string | null | undefined): boolean {
    return productId === LIFETIME_PRODUCT_ID;
}

export function isSubscriptionProduct(productId: string | null | undefined): boolean {
    return productId === MONTHLY_PRODUCT_ID || productId === YEARLY_PRODUCT_ID;
}

export async function verifySignedTransactionInfo(signedTransactionInfo: string): Promise<JWSTransactionDecodedPayload> {
    const environments: Environment[] = [
        Environment.LOCAL_TESTING,
        Environment.XCODE,
        Environment.SANDBOX,
    ];

    if (appleAppId) {
        environments.push(Environment.PRODUCTION);
    }

    let lastError: unknown;

    for (const environment of environments) {
        try {
            return await verifierFor(environment).verifyAndDecodeTransaction(signedTransactionInfo);
        } catch (error) {
            lastError = error;
        }
    }

    throw lastError instanceof Error ? lastError : new Error('transaction_verification_failed');
}

export function appleMsToIso(timestampMs?: number): string | null {
    if (!timestampMs || Number.isNaN(timestampMs)) return null;
    return new Date(timestampMs).toISOString();
}

function verifierFor(environment: Environment): SignedDataVerifier {
    const cached = verifierCache.get(environment);
    if (cached) return cached;

    const verifier = new SignedDataVerifier(
        appleRootCAs,
        false,
        environment,
        bundleId,
        environment === Environment.PRODUCTION ? appleAppId : undefined
    );
    verifierCache.set(environment, verifier);
    return verifier;
}

function loadAppleRootCAs(): Buffer[] {
    const certDir = path.resolve(process.cwd(), 'certs', 'apple');
    const files = [
        'AppleRootCA-G2.cer',
        'AppleRootCA-G3.cer',
    ];

    return files.map((file) => fs.readFileSync(path.join(certDir, file)));
}
