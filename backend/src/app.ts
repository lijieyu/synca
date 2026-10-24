import { supportedDocumentMimeTypeByExtension, allowedImageMimeTypes, imageExtensionForMimeType, supportedFileExtension, isSupportedDocument } from './attachmentPolicy.js';
import { createAIRouter, aiRateLimit } from './aiRoutes.js';
import { authenticate as authenticateAI, requireScope as requireAIScope, AIError, assertActive, type Actor, publicOrigin } from './aiCore.js';
import { prepareUpload, trackUpload, releaseUpload } from './storage.js';
import { db } from './db.js';
import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import path from 'path';
import fs from 'fs';
import cors from 'cors';
import multer from 'multer';
import { loginWithApple, getUserIdFromToken } from './auth.js';
import { assertCanCreateMessage, buildAccessStatus, buildLifetimeUpgradeOffer, DailyLimitError, reconcilePurchaseAccess } from './access.js';
import { appleMsToIso, isSupportedProduct, verifySignedTransactionInfo } from './iap.js';
import { renderLegalPage } from './legalPages.js';
import {
    listMessages, getMessage, createMessage, clearMessage, deleteMessage, clearAllMessages, deleteCompletedMessages, getUnclearedCount,
    upsertDevicePushToken, listActiveDevicePushTokens, upsertIapTransaction, createFeedback, getUser, assignLifetimeUpgradeCode,
    canUserAccessMedia, listMessageCategories, createMessageCategory, updateMessageCategory, deleteMessageCategory,
    updateMessageCategoryAssignment, reorderMessageCategories, deleteAccount,
    MessageWriteError,
} from './store.js';
import { apnsProvider } from './apns.js';

const app = express();

app.set('trust proxy', 1);

// CORS
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Upload-Size', 'X-Upload-ID', 'MCP-Protocol-Version', 'Mcp-Session-Id'],
    exposedHeaders: ['WWW-Authenticate', 'Mcp-Session-Id'],
}));

app.use(['/mcp', '/api/ai', '/oauth'], aiRateLimit);

// Only authenticated integrations may submit inline attachments. Other JSON APIs keep their existing small limit.
app.use(['/mcp', '/api/ai/tools/create_attachment'], async (req, res, next) => {
    try { await authenticateAI(req.header('Authorization')); next(); }
    catch (error) {
        if (error instanceof AIError) {
            res.setHeader('WWW-Authenticate', `Bearer resource_metadata="${publicOrigin()}/.well-known/oauth-protected-resource/mcp"`);
            res.status(error.status).json({ error: error.code });
        } else next(error);
    }
}, express.json({ limit: '8mb' }));
app.use(express.json());
app.use(createAIRouter(notifyOtherDevices));

// Serve uploaded images
const uploadsDir = path.resolve(process.cwd(), 'uploads');
if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
}
// Attachments are only served through authenticated /api/media routes.

const filesDir = path.resolve(process.cwd(), 'files');
if (!fs.existsSync(filesDir)) {
    fs.mkdirSync(filesDir, { recursive: true });
}

const feedbackUploadsDir = path.resolve(process.cwd(), 'feedback_uploads');
if (!fs.existsSync(feedbackUploadsDir)) {
    fs.mkdirSync(feedbackUploadsDir, { recursive: true });
}

const supportedCategoryColors = new Set(['sky', 'mint', 'amber', 'coral', 'violet', 'slate', 'rose', 'ocean']);
const attachmentMetadata = z.object({
    sourceDevice: z.string().max(50).optional(),
    categoryId: z.string().uuid().nullable().optional(),
    fileName: z.string().trim().min(1).max(255).optional(),
});

// Multer for image uploads
const messageStorage = multer.diskStorage({
    destination: (_req, _file, cb) => {
        cb(null, uploadsDir);
    },
    filename: (_req, file, cb) => {
        const ext = imageExtensionForMimeType(file.mimetype);
        const filename = `${uuidv4()}${ext}`;
        const id = (_req as any).res.locals.upload.reservationId;
        trackUpload(id, filename).then(() => cb(null, filename), error => cb(error, ''));
    },
});
const feedbackStorage = multer.diskStorage({
    destination: (_req, _file, cb) => {
        cb(null, feedbackUploadsDir);
    },
    filename: (_req, file, cb) => {
        const ext = imageExtensionForMimeType(file.mimetype);
        cb(null, `feedback-${uuidv4()}${ext}`);
    },
});
const fileStorage = multer.diskStorage({
    destination: (_req, _file, cb) => {
        cb(null, filesDir);
    },
    filename: (_req, file, cb) => {
        const ext = supportedFileExtension(file);
        const filename = `file-${uuidv4()}${ext ? `.${ext}` : ''}`;
        const id = (_req as any).res.locals.upload.reservationId;
        trackUpload(id, filename).then(() => cb(null, filename), error => cb(error, ''));
    },
});
const feedbackUpload = multer({
    storage: feedbackStorage,
    limits: { fileSize: 20 * 1024 * 1024 },
    fileFilter: (_req, file, cb) => {
        cb(null, allowedImageMimeTypes.includes(file.mimetype));
    },
});
const receiveAttachment = (kind: 'image' | 'file'): express.RequestHandler => (req, res, next) => {
    multer({ storage: kind === 'image' ? messageStorage : fileStorage,
        limits: { fileSize: res.locals.upload.bytes + 1, files: 1, fields: 4, fieldSize: 4096 },
        fileFilter: (_req, file, cb) => cb(null, kind === 'file' || allowedImageMimeTypes.includes(file.mimetype)),
    }).single(kind)(req, res, next);
};

function cleanupUploadedFiles(files: Express.Multer.File[] | undefined) {
    for (const file of files ?? []) {
        if (file.path && fs.existsSync(file.path)) {
            fs.unlinkSync(file.path);
        }
    }
}

// ── Auth middleware ──

async function auth(req: express.Request, res: express.Response, next: express.NextFunction) {
    if (req.header('Authorization')?.startsWith('Bearer synca_ai_')) {
        try {
            // Integration credentials are NEVER accepted by account, admin, purchases or legacy mutation routes.
            const upload = req.method === 'POST' && ['/messages/image', '/messages/file'].includes(req.path);
            const download = req.method === 'GET' && /^\/api\/media\/[^/]+$/.test(req.path);
            if (!upload && !download) return res.status(403).json({ error: 'use_ai_api' });
            const actor = await authenticateAI(req.header('Authorization'));
            requireAIScope(actor, 'attachments');
            requireAIScope(actor, upload ? 'create' : 'read');
            if (upload && (!req.header('X-Upload-ID') || !req.header('X-Upload-Size'))) return res.status(400).json({ error: 'upload_headers_required' });
            (req as any).userId = actor.userId;
            res.locals.aiActor = actor;
            return next();
        } catch (error) {
            if (error instanceof AIError) return res.status(error.status).json({ error: error.code });
            return next(error);
        }
    }
    const userId = await getUserIdFromToken(req.header('Authorization'));
    if (!userId) return res.status(401).json({ error: 'unauthorized' });
    (req as any).userId = userId;
    next();
}

async function adminAuth(req: express.Request, res: express.Response, next: express.NextFunction) {
    await auth(req, res, async () => {
        const userId = getUserId(req);
        const user = await getUser(userId);
        if (!user || !user.isAdmin) {
            return res.status(403).json({ error: 'forbidden_admin_only' });
        }
        next();
    });
}

function getUserId(req: express.Request): string {
    return (req as any).userId;
}

function getBaseUrl(req: express.Request): string {
    return `${req.protocol}://${req.get('host')}`;
}

// ── Routes ──

// Health check
app.get('/health', (_req, res) => {
    res.json({ ok: true, service: 'synca', now: new Date().toISOString() });
});

// Protected media access
app.get('/api/media/:filename', auth, async (req, res) => {
    const filename = req.params.filename;
    
    // Prevent directory traversal
    if (filename.includes('/') || filename.includes('..')) {
        return res.status(400).json({ error: 'invalid_filename' });
    }

    const userId = getUserId(req);
    const user = await getUser(userId);
    
    const attachment = await db.selectFrom('messages').select(['attachment_expires_at', 'attachment_purged', 'user_id'])
        .where(eb => eb.or([eb('image_path', '=', filename), eb('file_path', '=', filename)])).executeTakeFirst();
    if (attachment && attachment.user_id === userId && (attachment.attachment_purged ||
        (attachment.attachment_expires_at && attachment.attachment_expires_at <= new Date().toISOString()))) {
        return res.status(410).json({ error: 'attachment_expired' });
    }
    if (attachment && (attachment.attachment_purged || (attachment.attachment_expires_at && attachment.attachment_expires_at <= new Date().toISOString()))) {
        return res.status(403).json({ error: 'forbidden' });
    }
    res.setHeader('Cache-Control', 'private, no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const authorized = await canUserAccessMedia(userId, filename, res.locals.aiActor ? false : (user?.isAdmin ?? false));
    if (!authorized) {
        return res.status(403).json({ error: 'forbidden' });
    }

    const candidates = [
        path.join(uploadsDir, filename),
        path.join(filesDir, filename),
    ];
    const filePath = candidates.find((candidate) => fs.existsSync(candidate));
    if (!filePath) {
        return res.status(404).json({ error: 'not_found' });
    }

    const contentType = lookupMimeType(filePath);
    if (contentType) {
        res.type(contentType);
    }
    if (path.dirname(filePath) === filesDir) {
        // Documents are downloads, never executable content on our authenticated origin.
        res.attachment(filename);
        res.setHeader('Content-Security-Policy', "sandbox; default-src 'none'");
    }
    res.sendFile(filePath);
});

function lookupMimeType(filePath: string): string | null {
    const ext = path.extname(filePath).replace('.', '').toLowerCase();
    if (!ext) return null;
    if (supportedDocumentMimeTypeByExtension[ext]) {
        return supportedDocumentMimeTypeByExtension[ext];
    }
    switch (ext) {
        case 'png': return 'image/png';
        case 'jpg':
        case 'jpeg': return 'image/jpeg';
        case 'gif': return 'image/gif';
        case 'webp': return 'image/webp';
        case 'heic': return 'image/heic';
        case 'heif': return 'image/heif';
        default: return null;
    }
}

// Public legal and support pages
app.get('/:locale(en|zh-hans)/:pageKind(privacy-policy|terms-of-use|support)', (req, res) => {
    const html = renderLegalPage(
        req.params.locale as 'en' | 'zh-hans',
        req.params.pageKind as 'privacy-policy' | 'terms-of-use' | 'support',
    );

    if (!html) {
        return res.status(404).send('Not Found');
    }

    res.type('html').send(html);
});

// Sign in with Apple
app.post('/auth/apple', async (req, res) => {
    const parsed = z.object({
        idToken: z.string().min(1),
        deviceId: z.string().max(200).optional(),
        name: z.string().max(200).optional(),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    try {
        const result = await loginWithApple({
            idToken: parsed.data.idToken,
            deviceId: parsed.data.deviceId,
            name: parsed.data.name,
        });
        res.json(result);
    } catch (err) {
        console.error('[auth/apple] error:', err);
        const message = err instanceof Error ? err.message : 'auth_failed';
        res.status(401).json({ error: message });
    }
});

app.delete('/me/account', auth, async (req, res) => {
    const deleted = await deleteAccount({
        userId: getUserId(req),
        uploadsDir,
        filesDir,
        feedbackUploadsDir,
    });

    if (!deleted) {
        return res.status(404).json({ error: 'user_not_found' });
    }

    res.json({ ok: true });
});

// List messages (with optional since filter for sync)
app.get('/messages', auth, async (req, res) => {
    const since = req.query.since as string | undefined;
    const limit = req.query.limit ? Number(req.query.limit) : undefined;

    const messages = await listMessages({
        userId: getUserId(req),
        since: since?.trim() || undefined,
        limit: limit && limit > 0 ? limit : undefined,
        baseUrl: getBaseUrl(req),
    });

    res.json({ messages });
});

app.get('/message-categories', auth, async (req, res) => {
    const categories = await listMessageCategories(getUserId(req));
    res.json({ categories });
});

app.post('/message-categories', auth, async (req, res) => {
    const parsed = z.object({
        name: z.string().trim().min(1).max(40),
        color: z.string().trim().min(1).max(20),
    }).safeParse(req.body);

    if (!parsed.success || !supportedCategoryColors.has(parsed.data.color)) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    try {
        const category = await createMessageCategory({
            userId: getUserId(req),
            name: parsed.data.name,
            color: parsed.data.color as any,
            now: new Date().toISOString(),
        });
        res.status(201).json(category);
    } catch (error) {
        console.error('[message-categories/create] error:', error);
        res.status(409).json({ error: 'category_name_conflict' });
    }
});

app.patch('/message-categories/:id', auth, async (req, res) => {
    const parsed = z.object({
        name: z.string().trim().min(1).max(40).optional(),
        color: z.string().trim().min(1).max(20).optional(),
    }).safeParse(req.body);

    if (!parsed.success || (parsed.data.color && !supportedCategoryColors.has(parsed.data.color))) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    try {
        const category = await updateMessageCategory({
            id: req.params.id,
            userId: getUserId(req),
            name: parsed.data.name,
            color: parsed.data.color as any,
            now: new Date().toISOString(),
        });
        if (!category) {
            return res.status(404).json({ error: 'category_not_found_or_not_editable' });
        }
        res.json(category);
    } catch (error) {
        console.error('[message-categories/update] error:', error);
        res.status(409).json({ error: 'category_name_conflict' });
    }
});

app.put('/message-categories/order', auth, async (req, res) => {
    const parsed = z.object({
        categoryIds: z.array(z.string().trim().min(1)).max(100),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const reordered = await reorderMessageCategories({
        userId: getUserId(req),
        categoryIds: parsed.data.categoryIds,
        now: new Date().toISOString(),
    });

    if (!reordered) {
        return res.status(400).json({ error: 'invalid_category_order' });
    }

    notifyOtherDevices(getUserId(req), req.header('Authorization')).catch(() => {});
    res.json({ ok: true });
});

app.delete('/message-categories/:id', auth, async (req, res) => {
    const deleted = await deleteMessageCategory({
        id: req.params.id,
        userId: getUserId(req),
        now: new Date().toISOString(),
    });

    if (!deleted) {
        return res.status(404).json({ error: 'category_not_found_or_not_editable' });
    }

    notifyOtherDevices(getUserId(req), req.header('Authorization')).catch(() => {});
    res.json({ ok: true });
});

// Send text message
app.post('/messages', auth, async (req, res, next) => {
    try {
    if (typeof req.body?.textContent === 'string' && req.body.textContent.length > 2000) {
        return res.status(400).json({ error: 'message_too_long' });
    }

    const parsed = z.object({
        textContent: z.string().min(1).max(2000),
        sourceDevice: z.string().max(50).optional(),
        categoryId: z.string().uuid().optional().nullable(),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const userId = getUserId(req);
    const id = uuidv4();
    const now = new Date().toISOString();

    try {
        await assertCanCreateMessage(userId);
    } catch (error) {
        if (error instanceof DailyLimitError) {
            return res.status(403).json({ error: 'daily_limit_reached', accessStatus: error.accessStatus });
        }
        throw error;
    }

    await createMessage({
        id,
        userId,
        type: 'text',
        textContent: parsed.data.textContent,
        categoryId: parsed.data.categoryId,
        sourceDevice: parsed.data.sourceDevice,
        now,
    });

    const message = await getMessage(id, getBaseUrl(req));

    // Send silent push to other devices (fire-and-forget)
    notifyOtherDevices(userId, req.header('Authorization')).catch((err) => {
        console.error('[push] notify failed:', err);
    });

    res.status(201).json(message);
    } catch (error) { next(error); }
});

// Send image message
app.post('/messages/image', auth, prepareUpload('image'), receiveAttachment('image'), async (req, res, next) => {
    res.locals.upload.processing = true;
    try {
    if (req.aborted || res.destroyed) return;
    const file = (req as any).file;
    if (!file) {
        return res.status(400).json({ error: 'no_image_provided' });
    }

    if (file.size > res.locals.upload.bytes) {
        return res.status(413).json({ error: 'file_too_large' });
    }
    const metadata = attachmentMetadata.safeParse(req.body);
    if (!metadata.success) return res.status(400).json({ error: 'invalid_payload' });
    const userId = getUserId(req);
    const id = res.locals.upload.messageId;
    const now = new Date().toISOString();
    const sourceDevice = res.locals.aiActor ? `AI: ${res.locals.aiActor.name}`.slice(0, 50) : metadata.data.sourceDevice ?? null;
    const categoryId = metadata.data.categoryId ?? null;

    try {
        await assertCanCreateMessage(userId);
    } catch (error) {
        if (error instanceof DailyLimitError) {
            if (file?.path && fs.existsSync(file.path)) {
                fs.unlinkSync(file.path);
            }
            return res.status(403).json({ error: 'daily_limit_reached', accessStatus: error.accessStatus });
        }
        throw error;
    }

    const expiresAt = new Date(Date.now() + res.locals.upload.retentionDays * 86400000).toISOString();
    await createMessage({
        attachmentExpiresAt: expiresAt,
        reservationId: res.locals.upload.reservationId,
        beforeCommit: res.locals.aiActor ? async trx => {
            const actor = res.locals.aiActor as Actor;
            await assertActive(actor, trx);
            await trx.insertInto('ai_operations').values({ id: uuidv4(), user_id: actor.userId, connection_id: actor.id,
                kind: 'upload_attachment', payload: JSON.stringify({ messageId: id }), result: JSON.stringify({ id }),
                created_at: now, expires_at: null, status: 'completed', request_key: null }).execute();
        } : undefined,
        id,
        userId,
        type: 'image',
        imagePath: file.filename,
        fileSize: file.size,
        categoryId,
        sourceDevice,
        now,
    });

    const message = await getMessage(id, getBaseUrl(req));

    // Send silent push to other devices (fire-and-forget)
    notifyOtherDevices(userId, req.header('Authorization')).catch((err) => {
        console.error('[push] notify failed:', err);
    });

    res.status(201).json(message);
    } catch (error) { next(error); }
    finally { await releaseUpload(res.locals.upload.reservationId).catch(console.error); }
});

app.post('/messages/file', auth, prepareUpload('file'), receiveAttachment('file'), async (req, res, next) => {
    res.locals.upload.processing = true;
    try {
    if (req.aborted || res.destroyed) return;
    const file = (req as any).file as Express.Multer.File | undefined;
    if (!file) {
        return res.status(400).json({ error: 'no_file_provided' });
    }

    if (!isSupportedDocument(file)) {
        if (file.path && fs.existsSync(file.path)) {
            fs.unlinkSync(file.path);
        }
        return res.status(400).json({ error: 'unsupported_file_type' });
    }

    if (file.size > res.locals.upload.bytes) {
        return res.status(413).json({ error: 'file_too_large' });
    }
    const metadata = attachmentMetadata.safeParse(req.body);
    if (!metadata.success) return res.status(400).json({ error: 'invalid_payload' });
    const userId = getUserId(req);
    const id = res.locals.upload.messageId;
    const now = new Date().toISOString();
    const sourceDevice = res.locals.aiActor ? `AI: ${res.locals.aiActor.name}`.slice(0, 50) : metadata.data.sourceDevice ?? null;
    const categoryId = metadata.data.categoryId ?? null;

    try {
        await assertCanCreateMessage(userId);
    } catch (error) {
        if (error instanceof DailyLimitError) {
            if (file.path && fs.existsSync(file.path)) {
                fs.unlinkSync(file.path);
            }
            return res.status(403).json({ error: 'daily_limit_reached', accessStatus: error.accessStatus });
        }
        throw error;
    }

    const expiresAt = new Date(Date.now() + res.locals.upload.retentionDays * 86400000).toISOString();
    await createMessage({
        attachmentExpiresAt: expiresAt,
        reservationId: res.locals.upload.reservationId,
        beforeCommit: res.locals.aiActor ? async trx => {
            const actor = res.locals.aiActor as Actor;
            await assertActive(actor, trx);
            await trx.insertInto('ai_operations').values({ id: uuidv4(), user_id: actor.userId, connection_id: actor.id,
                kind: 'upload_attachment', payload: JSON.stringify({ messageId: id }), result: JSON.stringify({ id }),
                created_at: now, expires_at: null, status: 'completed', request_key: null }).execute();
        } : undefined,
        id,
        userId,
        type: 'file',
        filePath: file.filename,
        fileName: metadata.data.fileName || file.originalname,
        fileSize: file.size,
        fileMimeType: file.mimetype,
        categoryId,
        sourceDevice,
        now,
    });

    const message = await getMessage(id, getBaseUrl(req));

    notifyOtherDevices(userId, req.header('Authorization')).catch((err) => {
        console.error('[push] notify failed:', err);
    });

    res.status(201).json(message);
    } catch (error) { next(error); }
    finally { await releaseUpload(res.locals.upload.reservationId).catch(console.error); }
});

app.post('/feedback', auth, feedbackUpload.array('images', 3), async (req, res) => {
    const files = ((req as any).files as Express.Multer.File[] | undefined) ?? [];
    if (typeof req.body?.content === 'string' && req.body.content.trim().length > 2000) {
        cleanupUploadedFiles(files);
        return res.status(400).json({ error: 'feedback_too_long' });
    }

    const parsed = z.object({
        content: z.string().trim().min(1).max(2000),
        email: z.string().trim().email().max(320),
    }).safeParse(req.body);

    if (!parsed.success) {
        cleanupUploadedFiles(files);
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const now = new Date().toISOString();
    await createFeedback({
        id: uuidv4(),
        userId: getUserId(req),
        content: parsed.data.content,
        email: parsed.data.email,
        imagePaths: files.map((file) => file.filename),
        deviceModel: req.body.deviceModel,
        osVersion: req.body.osVersion,
        appVersion: req.body.appVersion,
        now,
    } as any);

    res.status(201).json({ ok: true });
});

// Clear single message
app.patch('/messages/:id/clear', auth, async (req, res) => {
    const userId = getUserId(req);
    const updated = await clearMessage(req.params.id, userId);
    if (!updated) {
        return res.status(404).json({ error: 'message_not_found_or_already_cleared' });
    }

    // Notify other devices about the clear
    notifyOtherDevices(userId, req.header('Authorization')).catch(() => {});

    res.json({ ok: true });
});

app.patch('/messages/:id/category', auth, async (req, res) => {
    const parsed = z.object({
        categoryId: z.string().uuid().nullable().optional(),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const message = await updateMessageCategoryAssignment({
        id: req.params.id,
        userId: getUserId(req),
        categoryId: parsed.data.categoryId,
        now: new Date().toISOString(),
        baseUrl: getBaseUrl(req),
    });

    if (!message) {
        return res.status(404).json({ error: 'message_not_found' });
    }

    notifyOtherDevices(getUserId(req), req.header('Authorization')).catch(() => {});
    res.json(message);
});

// Delete single message (True Delete)
app.delete('/messages/:id', auth, async (req, res) => {
    const userId = getUserId(req);
    const deleted = await deleteMessage(req.params.id, userId, uploadsDir, filesDir);
    if (!deleted) {
        return res.status(404).json({ error: 'message_not_found' });
    }

    // Notify other devices about the deletion
    notifyOtherDevices(userId, req.header('Authorization')).catch(() => {});

    res.json({ ok: true });
});

// Clear all messages
app.post('/messages/clear-all', auth, async (req, res) => {
    const userId = getUserId(req);
    const categoryId = typeof req.body?.categoryId === 'string' ? req.body.categoryId : null;
    const count = await clearAllMessages(userId, categoryId);

    // Notify other devices
    notifyOtherDevices(userId, req.header('Authorization')).catch(() => {});

    res.json({ ok: true, clearedCount: count });
});

// Delete completed messages
app.post('/messages/delete-completed', auth, async (req, res) => {
    const userId = getUserId(req);
    const categoryId = typeof req.body?.categoryId === 'string' ? req.body.categoryId : null;
    const count = await deleteCompletedMessages(userId, uploadsDir, filesDir, categoryId);

    // Notify other devices
    notifyOtherDevices(userId, req.header('Authorization')).catch(() => {});

    res.json({ ok: true, deletedCount: count });
});

// Get uncleared count (for badge)
app.get('/messages/uncleared-count', auth, async (req, res) => {
    const userId = getUserId(req);
    const count = await getUnclearedCount(userId);
    res.json({ count });
});

// ── Admin Routes ──

app.get('/api/admin/overview', adminAuth, async (req, res) => {
    const stats = await import('./store.js').then(s => s.getAdminOverviewStats());
    res.json(stats);
});

app.get('/api/admin/users', adminAuth, async (req, res) => {
    const users = await import('./store.js').then(s => s.getAdminUserList());
    res.json({ users });
});

app.get('/api/admin/messages/stats', adminAuth, async (req, res) => {
    const stats = await import('./store.js').then(s => s.getAdminMessageStats());
    res.json(stats);
});

app.get('/api/admin/revenue/stats', adminAuth, async (req, res) => {
    const stats = await import('./store.js').then(s => s.getAdminRevenueStats());
    res.json(stats);
});

app.get('/api/admin/feedback', adminAuth, async (req, res) => {
    const feedbacks = await import('./store.js').then(s => s.getAdminFeedbackList());
    res.json({ feedbacks });
});


app.get('/me/access-status', auth, async (req, res) => {
    const userId = getUserId(req);
    const accessStatus = await buildResponseAccessStatus(userId);
    const user = await getUser(userId);
    res.json({ userId, email: user?.email ?? null, isAdmin: user?.isAdmin ?? false, accessStatus });
});

app.post('/me/purchases/sync', auth, async (req, res) => {
    const parsed = z.object({
        signedTransactions: z.array(z.string().min(20)).min(1).max(20),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const userId = getUserId(req);
    const now = new Date();
    const nowIso = now.toISOString();

    for (const signedTransactionInfo of parsed.data.signedTransactions) {
        let transaction;
        try {
            transaction = await verifySignedTransactionInfo(signedTransactionInfo);
        } catch (error) {
            console.error('[purchase/sync] verification failed:', error);
            return res.status(400).json({ error: 'invalid_purchase_transaction' });
        }

        if (!isSupportedProduct(transaction.productId)) {
            continue;
        }

        if (transaction.appAccountToken && transaction.appAccountToken !== userId) {
            return res.status(403).json({ error: 'purchase_account_mismatch' });
        }

        if (!transaction.transactionId) {
            return res.status(400).json({ error: 'purchase_transaction_missing_id' });
        }

        await upsertIapTransaction({
            transactionId: transaction.transactionId,
            originalTransactionId: transaction.originalTransactionId ?? null,
            userId,
            productId: transaction.productId,
            environment: transaction.environment ?? 'Unknown',
            type: typeof transaction.type === 'string' ? transaction.type : null,
            appAccountToken: transaction.appAccountToken ?? null,
            purchaseDate: appleMsToIso(transaction.purchaseDate),
            originalPurchaseDate: appleMsToIso(transaction.originalPurchaseDate),
            expiresAt: appleMsToIso(transaction.expiresDate),
            revocationDate: appleMsToIso(transaction.revocationDate),
            isUpgraded: Boolean(transaction.isUpgraded),
            signedTransactionInfo,
            now: nowIso,
        });
    }

    await reconcilePurchaseAccess(userId, now);
    const accessStatus = await buildResponseAccessStatus(userId, now);
    const user = await getUser(userId);
    notifyOtherDevices(userId, req.header('Authorization')).catch((err) => {
        console.error('[purchase/sync] notify failed:', err);
    });
    res.json({ ok: true, userId, email: user?.email ?? null, accessStatus });
});

app.post('/me/lifetime-upgrade-offer-code', auth, async (req, res) => {
    const parsed = z.object({
        kind: z.enum(['monthly_to_lifetime', 'yearly_to_lifetime']),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const userId = getUserId(req);
    const accessStatus = await buildResponseAccessStatus(userId);
    const offer = accessStatus.lifetimeUpgradeOffer;

    if (!offer || offer.kind !== parsed.data.kind) {
        return res.status(403).json({ error: 'offer_not_eligible' });
    }

    const now = new Date().toISOString();
    const assigned = await assignLifetimeUpgradeCode(userId, parsed.data.kind, now);
    if (!assigned) {
        return res.status(409).json({ error: 'offer_code_unavailable' });
    }

    return res.json({
        ok: true,
        kind: parsed.data.kind,
        code: assigned.code,
        discountedPriceLabel: offer.discountedPriceLabel,
    });
});

// Update user timezone
app.post('/me/timezone', auth, async (req, res) => {
    const parsed = z.object({
        offsetSeconds: z.number().int().min(-43200).max(50400),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const userId = getUserId(req);
    await import('./db.js').then(({ db }) =>
        db.updateTable('users')
            .set({ timezone_offset_seconds: parsed.data.offsetSeconds, updated_at: new Date().toISOString() })
            .where('id', '=', userId)
            .execute()
    );

    res.json({ ok: true });
});

// Register/update push token
app.post('/me/push-token', auth, async (req, res) => {
    const parsed = z.object({
        token: z.string().regex(/^[0-9a-fA-F]{64,256}$/),
        platform: z.enum(['ios', 'macos']).default('ios'),
        apnsEnvironment: z.enum(['production', 'sandbox']).optional(),
        topic: z.string().min(1).max(200).optional(),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const userId = getUserId(req);
    const now = new Date().toISOString();
    const normalizedToken = parsed.data.token.replace(/\s+/g, '').toLowerCase();

    await upsertDevicePushToken({
        id: uuidv4(),
        userId,
        platform: parsed.data.platform,
        token: normalizedToken,
        apnsEnvironment: parsed.data.apnsEnvironment ?? 'production',
        topic: parsed.data.topic,
        now,
    });

    res.json({ ok: true });
});

// ── Push notification helper ──

/**
 * Send a silent push notification to all other devices of the user
 * to trigger an immediate sync.
 */
async function notifyOtherDevices(userId: string, authHeader?: string): Promise<void> {
    const tokens = await listActiveDevicePushTokens(userId);
    if (tokens.length === 0) return;

    const badge = await getUnclearedCount(userId);

    await apnsProvider.send(
        {
            userId,
            badge,
            kind: 'background',
            data: { syncTrigger: true },
        },
        tokens.map((t) => ({
            token: t.token,
            apnsEnvironment: t.apnsEnvironment,
            topic: t.topic,
        })),
    );
}

async function buildResponseAccessStatus(userId: string, now?: Date) {
    const accessStatus = await buildAccessStatus(userId, now);
    accessStatus.lifetimeUpgradeOffer = await buildLifetimeUpgradeOffer(userId, accessStatus);
    return accessStatus;
}

app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
    if (err instanceof AIError) return res.status(err.status).json({ error: err.code });
    if (err instanceof multer.MulterError) {
        const error = err.code === 'LIMIT_FILE_SIZE' ? 'file_too_large' : 'invalid_upload';
        return res.status(err.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({ error });
    }
    if (err instanceof MessageWriteError) {
        const status = err.code === 'unauthorized' ? 401 : err.code === 'upload_cancelled' ? 409 :
            err.code === 'storage_limit_reached' ? 413 : 403;
        if (err.code === 'daily_limit_reached' || err.code === 'file_upload_requires_paid') {
            void buildAccessStatus(getUserId(req)).then(accessStatus => {
                res.status(status).json({ error: err.code, accessStatus });
            }).catch(next);
        } else res.status(status).json({ error: err.code });
        return;
    }
    next(err);
});

export default app;
