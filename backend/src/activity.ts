import type { Request, Response } from 'express';
import { sqlite } from './db.js';

// Route templates avoid counting unknown URLs, admin requests or integration tokens.
// A successful empty sync still means the authenticated client was active.
const readRoutes = new Set([
    '/messages', '/messages/uncleared-count', '/message-categories',
    '/me/access-status', '/api/media/:filename',
]);
const operationRoutes = new Set([
    '/messages', '/messages/image', '/messages/file', '/messages/:id',
    '/messages/:id/text', '/messages/:id/completion', '/messages/:id/clear',
    '/messages/:id/category', '/messages/clear-all', '/messages/delete-completed',
    '/message-categories', '/message-categories/:id', '/message-categories/order',
]);

export function activityDate(now: Date): string {
    return new Date(now.getTime() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

export function recordActivity(userId: string, date: string, operation: boolean): void {
    // Same SQLite connection as business writes. The guarded insert prevents a late
    // response from resurrecting activity after concurrent account deletion.
    sqlite.prepare(`
        INSERT INTO daily_activities(user_id, activity_date, has_read, has_operation)
        SELECT id, ?, ?, ? FROM users WHERE id = ?
        ON CONFLICT(activity_date, user_id) DO UPDATE SET
            has_read = MAX(has_read, excluded.has_read),
            has_operation = MAX(has_operation, excluded.has_operation)
        WHERE has_read < excluded.has_read OR has_operation < excluded.has_operation
    `).run(date, Number(!operation), Number(operation), userId);
}

export function trackActivity(req: Request, res: Response, userId: string): void {
    res.once('finish', () => {
        const route = req.route?.path;
        const isRead = req.method === 'GET' && readRoutes.has(route);
        const isOperation = ['POST', 'PATCH', 'PUT', 'DELETE'].includes(req.method)
            && operationRoutes.has(route);
        if ((!isRead && !isOperation) || res.statusCode < 200 || res.statusCode >= 300) return;
        try {
            recordActivity(userId, activityDate(new Date()), isOperation);
        } catch {
            // Analytics failures must not change successful business responses.
            console.error('[activity] Failed to persist daily activity');
        }
    });
}
