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
} from './store.js';
import { apnsProvider } from './apns.js';

const app = express();

// CORS
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
}));

app.use(express.json());

// Serve uploaded images
const uploadsDir = path.resolve(process.cwd(), 'uploads');
if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
}
app.use('/uploads', express.static(uploadsDir));

const feedbackUploadsDir = path.resolve(process.cwd(), 'feedback_uploads');
if (!fs.existsSync(feedbackUploadsDir)) {
    fs.mkdirSync(feedbackUploadsDir, { recursive: true });
}

const allowedImageMimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'image/gif'];

// Multer for image uploads
const messageStorage = multer.diskStorage({
    destination: (_req, _file, cb) => {
        cb(null, uploadsDir);
    },
    filename: (_req, file, cb) => {
        const ext = imageExtensionForMimeType(file.mimetype);
        cb(null, `${uuidv4()}${ext}`);
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
const upload = multer({
    storage: messageStorage,
    limits: { fileSize: 20 * 1024 * 1024 }, // 20MB
    fileFilter: (_req, file, cb) => {
        cb(null, allowedImageMimeTypes.includes(file.mimetype));
    },
});
const feedbackUpload = multer({
    storage: feedbackStorage,
    limits: { fileSize: 20 * 1024 * 1024 },
    fileFilter: (_req, file, cb) => {
        cb(null, allowedImageMimeTypes.includes(file.mimetype));
    },
});

function imageExtensionForMimeType(mimeType: string): string {
    switch (mimeType) {
        case 'image/jpeg': return '.jpg';
        case 'image/webp': return '.webp';
        case 'image/heic': return '.heic';
        case 'image/heif': return '.heif';
        case 'image/gif': return '.gif';
        default: return '.png';
    }
}

function cleanupUploadedFiles(files: Express.Multer.File[] | undefined) {
    for (const file of files ?? []) {
        if (file.path && fs.existsSync(file.path)) {
            fs.unlinkSync(file.path);
        }
    }
}

// ── Auth middleware ──

async function auth(req: express.Request, res: express.Response, next: express.NextFunction) {
    const userId = await getUserIdFromToken(req.header('Authorization'));
    if (!userId) return res.status(401).json({ error: 'unauthorized' });
    (req as any).userId = userId;
    next();
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
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    try {
        const result = await loginWithApple({
            idToken: parsed.data.idToken,
            deviceId: parsed.data.deviceId,
        });
        res.json(result);
    } catch (err) {
        console.error('[auth/apple] error:', err);
        const message = err instanceof Error ? err.message : 'auth_failed';
        res.status(401).json({ error: message });
    }
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

// Send text message
app.post('/messages', auth, async (req, res) => {
    if (typeof req.body?.textContent === 'string' && req.body.textContent.length > 2000) {
        return res.status(400).json({ error: 'message_too_long' });
    }

    const parsed = z.object({
        textContent: z.string().min(1).max(2000),
        sourceDevice: z.string().max(50).optional(),
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
        sourceDevice: parsed.data.sourceDevice,
        now,
    });

    const message = await getMessage(id, getBaseUrl(req));

    // Send silent push to other devices (fire-and-forget)
    notifyOtherDevices(userId, req.header('Authorization')).catch((err) => {
        console.error('[push] notify failed:', err);
    });

    res.status(201).json(message);
});

// Send image message
app.post('/messages/image', auth, upload.single('image'), async (req, res) => {
    const file = (req as any).file;
    if (!file) {
        return res.status(400).json({ error: 'no_image_provided' });
    }

    const userId = getUserId(req);
    const id = uuidv4();
    const now = new Date().toISOString();
    const sourceDevice = req.body?.sourceDevice ?? null;

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

    await createMessage({
        id,
        userId,
        type: 'image',
        imagePath: file.filename,
        sourceDevice,
        now,
    });

    const message = await getMessage(id, getBaseUrl(req));

    // Send silent push to other devices (fire-and-forget)
    notifyOtherDevices(userId, req.header('Authorization')).catch((err) => {
        console.error('[push] notify failed:', err);
    });

    res.status(201).json(message);
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
        now,
    });

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

// Delete single message (True Delete)
app.delete('/messages/:id', auth, async (req, res) => {
    const userId = getUserId(req);
    const deleted = await deleteMessage(req.params.id, userId, uploadsDir);
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
    const count = await clearAllMessages(userId);

    // Notify other devices
    notifyOtherDevices(userId, req.header('Authorization')).catch(() => {});

    res.json({ ok: true, clearedCount: count });
});

// Delete completed messages
app.post('/messages/delete-completed', auth, async (req, res) => {
    const userId = getUserId(req);
    const count = await deleteCompletedMessages(userId);

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

app.get('/me/access-status', auth, async (req, res) => {
    const userId = getUserId(req);
    const accessStatus = await buildResponseAccessStatus(userId);
    const user = await getUser(userId);
    res.json({ userId, email: user?.email ?? null, accessStatus });
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

app.use((err: any, _req: express.Request, res: express.Response, next: express.NextFunction) => {
    if (err instanceof multer.MulterError) {
        const error = err.code === 'LIMIT_FILE_SIZE' ? 'file_too_large' : 'invalid_upload';
        return res.status(400).json({ error });
    }
    next(err);
});

export default app;
