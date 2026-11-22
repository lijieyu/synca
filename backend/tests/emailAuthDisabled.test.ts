import { afterAll, expect, it, vi } from 'vitest';
import request from 'supertest';
vi.hoisted(() => {
  vi.stubEnv('SYNCA_EMAIL_AUTH_ENABLED', undefined);
  vi.stubEnv('EMAIL_AUTH_SECRET', 'test-only-preloaded-credentials-do-not-enable-routes');
  vi.stubEnv('ALIYUN_DM_ACCESS_KEY_ID', 'fixture-not-an-actual-key');
  vi.stubEnv('ALIYUN_DM_ACCESS_KEY_SECRET', 'fixture-not-an-actual-secret');
});
afterAll(() => vi.unstubAllEnvs());
import app from '../src/app.js';
it('does not mount email sign-in or binding without explicit opt-in even if credentials are preloaded', async () => {
  for(const route of ['/auth/email/code','/auth/email/verify','/me/login-methods/email/code','/me/login-methods/email/verify']) {
    expect((await request(app).post(route).send({email:'synthetic@example.invalid'})).status).toBe(404);
  }
});
