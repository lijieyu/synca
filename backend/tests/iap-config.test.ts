import { afterEach, expect, it, vi } from 'vitest';

// Reproduce a process whose Apple settings exist only in .env, not its shell.
const state = vi.hoisted(() => ({ environments: [] as string[] }));
vi.mock('dotenv/config', () => {
    process.env.APP_STORE_APPLE_ID = '6761647007';
    process.env.APPLE_CLIENT_ID = 'org.haerth.synca';
    return {};
});
vi.mock('@apple/app-store-server-library', async () => {
    const actual = await vi.importActual<typeof import('@apple/app-store-server-library')>('@apple/app-store-server-library');
    return { ...actual, SignedDataVerifier: class {
        constructor(_roots: Buffer[], _online: boolean, private environment: string,
            private bundle: string, private appId?: number) {}
        async verifyAndDecodeTransaction() {
            state.environments.push(this.environment);
            if (this.environment !== 'Production') throw new Error('environment mismatch');
            expect(this.bundle).toBe('org.haerth.synca');
            expect(this.appId).toBe(6761647007);
            return { transactionId: 'verified-production', environment: 'Production' };
        }
    } };
});
afterEach(() => vi.unstubAllEnvs());
it('loads .env before constructing the production purchase verifier', async () => {
    vi.stubEnv('APP_STORE_APPLE_ID', undefined);
    vi.stubEnv('APPLE_CLIENT_ID', undefined);
    const { verifySignedTransactionInfo } = await import('../src/iap.js');
    await expect(verifySignedTransactionInfo('synthetic-test-input')).resolves.toMatchObject({
        transactionId: 'verified-production', environment: 'Production',
    });
    expect(state.environments).toContain('Production');
});
