import { afterEach, expect, it, vi } from 'vitest';
import express from 'express';
import request from 'supertest';
import { requestContext, operationalErrors } from '../src/observability.js';
afterEach(() => vi.restoreAllMocks());
it('logs a request ID, safe route and timestamp without payload, URL or credentials', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {});
    const app = express(); app.use(requestContext);
    app.get('/test/:id', (_req, _res, next) => next(new Error('secret body and token')));
    app.use(operationalErrors);
    const res = await request(app).get('/test/private-id?token=secret').set('Authorization', 'Bearer secret');
    expect(res.status).toBe(500);
    expect(res.headers['x-request-id']).toMatch(/^[a-f0-9-]{36}$/);
    const events = log.mock.calls.map(c => JSON.parse(String(c[0])));
    expect(events.find(e => e.event === 'http.error')).toMatchObject({ route: '/test/:id', requestId: res.headers['x-request-id'] });
    expect(events.every(e => !isNaN(Date.parse(e.time)))).toBe(true);
    expect(JSON.stringify(events)).not.toMatch(/private-id|secret|Bearer/);
});
it('classifies aborted uploads without logging an internal error', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const app = express(); app.use(requestContext);
    app.post('/upload', (_req, _res, next) => next(Object.assign(new Error('Request aborted'), { code: 'ECONNABORTED' })));
    app.use(operationalErrors);
    const res = await request(app).post('/upload');
    expect(res.status).toBe(400); expect(res.body.error).toBe('upload_cancelled');
    expect(error).not.toHaveBeenCalled(); expect(warn).toHaveBeenCalledOnce();
});
it('preserves the JSON parser size and syntax error status', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const app = express(); app.use(requestContext, express.json({ limit: '16b' }));
    app.post('/json', (_req, res) => res.json({ ok: true })); app.use(operationalErrors);
    expect((await request(app).post('/json').set('Content-Type', 'application/json').send('{bad')).status).toBe(400);
    expect((await request(app).post('/json').send({ value: 'a'.repeat(20) })).status).toBe(413);
    expect((await request(app).post('/json').set('Content-Type', 'application/json; charset=bogus').send('{}')).status).toBe(415);
});
