import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import path from 'path';
import fs from 'fs';
import cors from 'cors';
import multer from 'multer';
import { loginWithApple, getUserIdFromToken } from './auth.js';
import {
    listMessages, getMessage, createMessage, clearMessage, clearAllMessages, getUnclearedCount,
    upsertDevicePushToken, listActiveDevicePushTokens,
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

// Multer for image uploads
const storage = multer.diskStorage({
    destination: (_req, _file, cb) => {
        cb(null, uploadsDir);
    },
    filename: (_req, file, cb) => {
        const ext = imageExtensionForMimeType(file.mimetype);
        cb(null, `${uuidv4()}${ext}`);
    },
});
const upload = multer({
    storage,
    limits: { fileSize: 20 * 1024 * 1024 }, // 20MB
    fileFilter: (_req, file, cb) => {
        const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'image/gif'];
        cb(null, allowed.includes(file.mimetype));
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
    const parsed = z.object({
        textContent: z.string().min(1).max(10000),
        sourceDevice: z.string().max(50).optional(),
    }).safeParse(req.body);

    if (!parsed.success) {
        return res.status(400).json({ error: 'invalid_payload' });
    }

    const userId = getUserId(req);
    const id = uuidv4();
    const now = new Date().toISOString();

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

// Clear all messages
app.post('/messages/clear-all', auth, async (req, res) => {
    const userId = getUserId(req);
    const count = await clearAllMessages(userId);

    // Notify other devices
    notifyOtherDevices(userId, req.header('Authorization')).catch(() => {});

    res.json({ ok: true, clearedCount: count });
});

// Get uncleared count (for badge)
app.get('/messages/uncleared-count', auth, async (req, res) => {
    const userId = getUserId(req);
    const count = await getUnclearedCount(userId);
    res.json({ count });
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

export default app;
