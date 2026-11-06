import { randomUUID } from 'node:crypto';
import type { RequestHandler, ErrorRequestHandler } from 'express';

// Only caller-selected, non-sensitive fields belong here; never pass request bodies or headers.
export function logEvent(level: 'info' | 'warn' | 'error', event: string, fields: Record<string, unknown> = {}) {
    console[level](JSON.stringify({ ...fields, time: new Date().toISOString(), level, event }));
}
export const requestContext: RequestHandler = (req, res, next) => {
    res.locals.requestId = randomUUID();
    res.setHeader('X-Request-ID', res.locals.requestId);
    const start = Date.now();
    res.once('finish', () => {
        if (res.statusCode >= 500) logEvent('error', 'http.server_error', {
            requestId: res.locals.requestId, method: req.method,
            route: req.route?.path ?? 'unmatched', status: res.statusCode, durationMs: Date.now() - start,
        });
    });
    next();
};

export function errorFields(error: unknown) {
    const e = error as { name?: unknown; code?: unknown; stack?: unknown };
    return {
        errorType: typeof e?.name === 'string' && /^[A-Za-z]{1,60}$/.test(e.name) ? e.name : 'Error',
        code: typeof e?.code === 'string' && /^[A-Z0-9_]{1,60}$/.test(e.code) ? e.code : undefined,
        // Keep only application file/line locations, never error messages, arguments, URLs or payloads.
        locations: typeof e?.stack === 'string' ? (e.stack.match(/(?:src|node_modules)\/[A-Za-z0-9_./-]+\.[cm]?[jt]s:\d+:\d+/g) ?? []).slice(0, 5) : [],
    };
}
export const operationalErrors: ErrorRequestHandler = (error, req, res, next) => {
    const cancelled = req.aborted || error?.code === 'ECONNABORTED' || error?.message === 'Request aborted';
    const fields = { requestId: res.locals.requestId, method: req.method, route: req.route?.path ?? 'unmatched', ...errorFields(error) };
    if (cancelled) {
        logEvent('warn', 'upload.cancelled', fields);
        if (!res.headersSent && !res.destroyed) res.status(400).json({ error: 'upload_cancelled' });
        return;
    }
    const clientStatus = Number.isInteger(error?.status) && error.status >= 400 && error.status < 500 ? error.status as number : undefined;
    logEvent(clientStatus ? 'warn' : 'error', 'http.error', fields);
    if (res.headersSent) { next(error); return; }
    res.status(clientStatus ?? 500).json({ error: clientStatus === 413 ? 'payload_too_large' : clientStatus === 415 ? 'unsupported_media_type' : clientStatus ? 'invalid_payload' : 'internal_error', requestId: res.locals.requestId });
};
