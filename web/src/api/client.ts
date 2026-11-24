export interface SyncState { messages: string; categories: string; access: string; latestMessage: string | null; count: number }
import { saveDownload } from '../utils/downloads';
export class SessionExpiredError extends Error {}
export class AuthError extends Error {
  readonly code: string;
  readonly retryAfter?: number;
  constructor(code: string, retryAfter?: number) { super(code); this.code = code; this.retryAfter = retryAfter; }
}
export interface EmailChallenge { challengeId: string; expiresAt: string; resendAt: string }
export interface LoginMethods { apple: boolean; email: string | null }

export class MessageEditError extends Error {
  readonly code: 'message_edit_conflict' | 'message_not_found' | 'message_not_text';
  constructor(code: MessageEditError['code']) { super(code); this.code = code; }
}

const BASE_URL = '';
const ATTACHMENT_CACHE_NAME = 'synca-attachment-cache-v1';

export interface SyncaMessage {
  attachmentExpiresAt?: string | null;
  attachmentExpired?: boolean;
  id: string;
  sourceDevice: string;
  textContent: string | null;
  imagePath: string | null;
  imageUrl: string | null;
  filePath: string | null;
  fileUrl: string | null;
  fileName: string | null;
  fileSize: number | null;
  fileMimeType: string | null;
  categoryId: string | null;
  categoryName: string | null;
  categoryColor: MessageCategoryColor | null;
  categoryColorHex?: string | null;
  categoryIsDefault: boolean;
  type: 'text' | 'image' | 'file';
  isCleared: boolean;
  isDeleted: boolean;
  createdAt: string;
  updatedAt: string;
}

export type MessageCategoryColor = 'sky' | 'mint' | 'amber' | 'coral' | 'violet' | 'slate' | 'rose' | 'ocean';

export interface MessageCategory {
  id: string;
  userId: string;
  name: string;
  color: MessageCategoryColor;
  colorHex?: string | null;
  isDefault: boolean;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
}

export class DailyLimitError extends Error {
  constructor() {
    super('Daily limit reached');
    this.name = 'DailyLimitError';
  }
}

export interface SyncaUser {
  id: string;
  email: string;
  isAdmin: boolean;
}

export interface AccessStatus {
  storage?: { usedBytes: number; limitBytes: number; imageLimitBytes: number; fileLimitBytes: number; retentionDays: number; canUploadFiles: boolean };
  plan: 'trial' | 'free' | 'unlimited';
  unlimitedSource?: 'subscription' | 'lifetime' | null;
  purchaseDate?: string | null;
  subscriptionExpiresAt?: string | null;
  storeProductId?: string | null;
  isUnlimited: boolean;
  isTrial: boolean;
  daysLeft: number | null;
  todayUsed: number;
  todayLimit: number | null;
}

export interface ProfileResponse {
  userId: string;
  email: string | null;
  isAdmin: boolean;
  accessStatus: AccessStatus;
}

export interface AuthResponse {
  token: string;
  user: {
    id: string;
    email: string;
    isAdmin: boolean;
  };
}

export class StorageError extends Error {
  readonly code: string;
  constructor(code: string) { super(code); this.code = code; }
}
export interface UploadOptions { signal: AbortSignal; onProgress: (value: number) => void }
export interface AttachmentOptions { signal?: AbortSignal; expiresAt?: string | null; cacheImage?: boolean }
const IMAGE_CACHE_LIMIT_BYTES = 16 * 1024 * 1024;
const IMAGE_CACHE_ITEM_LIMIT_BYTES = 4 * 1024 * 1024;
// Keep only the latest uploaded original; downloaded images retain their smaller limits.
const UPLOADED_IMAGE_LIMIT_BYTES = 20 * 1024 * 1024;
const IMAGE_CACHE_TTL_MS = 60 * 1000;

class APIClient {
  // A missing capability is an older server, not an expired account session.
  async emailAvailable(signal?: AbortSignal, legacyPreview = false): Promise<boolean> {
    try {
      const headers: Record<string,string> = typeof window !== 'undefined' && window.syncaDesktop?.emailAuth === true ? {'X-Synca-Client':'desktop'} : {};
      const response = await fetch('/auth/capabilities', {headers, signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(5000)]) : AbortSignal.timeout(5000), cache:'no-store'});
      if (response.status === 404) return legacyPreview;
      if (!response.ok) return false;
      const capabilities: unknown = await response.json();
      return typeof capabilities === 'object' && capabilities !== null && 'email' in capabilities && capabilities.email === true;
    } catch { return false; }
  }

  constructor() {
    if (typeof window !== 'undefined' && 'caches' in window) void caches.delete(ATTACHMENT_CACHE_NAME).catch(() => {});
  }
  private readonly editingDrafts = new Set<() => void>();
  private pendingSessionReload = false;

  /** Let users copy or dismiss an open draft before returning them to sign-in. */
  retainEditingDraft(onSessionExpired: () => void): () => void {
    this.editingDrafts.add(onSessionExpired);
    return () => {
      this.editingDrafts.delete(onSessionExpired);
      if (this.pendingSessionReload && this.editingDrafts.size === 0) {
        queueMicrotask(() => {
          if (this.pendingSessionReload && this.editingDrafts.size === 0) {
            this.pendingSessionReload = false;
            window.location.reload();
          }
        });
      }
    };
  }

  private readonly imageCache = new Map<string, { blob: Blob; expiresAt: number; objectURL?: string }>();
  private uploadedImage: { url: string; blob: Blob; expiresAt: number; objectURL?: string } | null = null;
  private sessionVersion = 0;
  private imageCacheToken: string | null = null;
  private readonly attachmentRequests = new Set<AbortController>();
  private readonly activeUploads = new Set<XMLHttpRequest>();

  // Never persist protected attachments: an old browser cache must not bypass expiry or sign-out.
  resetSession() {
    this.sessionVersion += 1;
    this.clearImageSources();
    this.imageCacheToken = this.token;
    this.attachmentRequests.forEach(controller => controller.abort());
    this.attachmentRequests.clear();
    this.activeUploads.forEach(xhr => xhr.abort());
    this.activeUploads.clear();
    this.messageDeltaCache = null;
    if ('caches' in window) void caches.delete(ATTACHMENT_CACHE_NAME).catch(() => {});
  }

  private readonly uploadIDs = new WeakMap<File, string>();
  private get token(): string | null {
    return localStorage.getItem('authToken');
  }

  private async fetch<T>(path: string, options: RequestInit = {}, anonymous = false): Promise<T> {
    const requestToken = this.token;
    const headers: Record<string, string> = {
      ...(!options.body || typeof options.body === 'string' ? { 'Content-Type': 'application/json' } : {}),
      ...(options.headers as Record<string, string>),
    };

    if (requestToken && !anonymous) {
      headers['Authorization'] = `Bearer ${requestToken}`;
    }

    const response = await fetch(`${BASE_URL}${path}`, {
      ...options,
      headers,
    });

    return this.decodeResponse<T>(response, requestToken, anonymous);
  }

  private async decodeResponse<T>(response: Response, requestToken: string | null, anonymous = false): Promise<T> {
    if (requestToken !== this.token) throw new DOMException('Session changed', 'AbortError');

    if (response.status === 401 && !anonymous) {
      localStorage.removeItem('authToken');
      this.resetSession();
      if (this.editingDrafts.size > 0) {
        this.pendingSessionReload = true;
        this.editingDrafts.forEach(onExpired => onExpired());
      } else window.location.reload();
      throw new SessionExpiredError('Unauthorized');
    }

    if (!response.ok) {
      const errorText = await response.text();
      if (requestToken !== this.token) throw new DOMException('Session changed', 'AbortError');
      try {
        const errorJson = JSON.parse(errorText);
        if (typeof errorJson.error === 'string' && (anonymous || response.url.includes('/login-methods') || ['invalid_payload','invalid_email','invalid_code','code_expired','code_attempts_exceeded','apple_auth_failed','email_in_use','apple_in_use','email_already_bound','apple_already_bound','rate_limited','email_unavailable','email_send_failed'].includes(errorJson.error))) throw new AuthError(errorJson.error, errorJson.retryAfter);
        if (['message_edit_conflict', 'message_not_found', 'message_not_text'].includes(errorJson.error)) throw new MessageEditError(errorJson.error);
        if (['file_upload_requires_paid', 'storage_limit_reached', 'attachment_expired', 'file_too_large'].includes(errorJson.error)) throw new StorageError(errorJson.error);
        if (response.status === 403 && errorJson.error === 'daily_limit_reached') {
          throw new DailyLimitError();
        }
      } catch (e) {
        if (e instanceof AuthError || e instanceof DailyLimitError || e instanceof StorageError || e instanceof MessageEditError) throw e;
      }
      throw new Error(`API Error: ${response.status} ${errorText}`);
    }

    const result = await response.json();
    if (requestToken !== this.token) throw new DOMException('Session changed', 'AbortError');
    return result;
  }

  // One private, session-scoped response only; never persist deltas as a full list.
  private messageDeltaCache: { token: string | null; since: string; etag: string; value: { messages: SyncaMessage[] } } | null = null;

  getSyncState(): Promise<SyncState> { return this.fetch('/sync/state', { cache: 'no-store' }); }

  async listMessageChanges(since: string): Promise<{ messages: SyncaMessage[] }> {
    const token = this.token;
    const cached = this.messageDeltaCache?.token === token && this.messageDeltaCache.since === since ? this.messageDeltaCache : null;
    const response = await fetch(`/messages?since=${encodeURIComponent(since)}`, {
      cache: 'no-store',
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        // Explicit max-age permits origin ETag validation while no-store prevents
        // disk caching of protected record content in the browser.
        'Cache-Control': 'max-age=0',
        ...(cached ? { 'If-None-Match': cached.etag } : {}),
      },
    });
    if (token !== this.token) throw new DOMException('Session changed', 'AbortError');
    if (response.status === 304 && cached) return cached.value;
    const value = await this.decodeResponse<{ messages: SyncaMessage[] }>(response, token);
    const etag = response.headers.get('ETag');
    this.messageDeltaCache = etag ? { token, since, etag, value } : null;
    return value;
  }

  sendEmailCode(email: string, locale: string, binding = false, signal?: AbortSignal): Promise<EmailChallenge> {
    return this.fetch(binding ? '/me/login-methods/email/code' : '/auth/email/code', { method: 'POST', body: JSON.stringify({ email, locale }), signal }, !binding);
  }
  verifyEmailCode(challengeId: string, code: string, signal?: AbortSignal): Promise<AuthResponse> {
    return this.fetch('/auth/email/verify', { method: 'POST', body: JSON.stringify({ challengeId, code }), signal }, true);
  }
  getLoginMethods(signal?: AbortSignal): Promise<LoginMethods> { return this.fetch('/me/login-methods', { signal }); }
  bindEmail(challengeId: string, code: string, signal?: AbortSignal): Promise<LoginMethods> {
    return this.fetch('/me/login-methods/email/verify', { method: 'POST', body: JSON.stringify({ challengeId, code }), signal });
  }
  appleBindingChallenge(signal?: AbortSignal): Promise<{challengeId: string; nonce: string; expiresAt?: string}> {
    return this.fetch('/me/login-methods/apple/challenge', { method: 'POST', signal });
  }
  bindApple(challengeId: string, idToken: string, signal?: AbortSignal): Promise<LoginMethods> {
    return this.fetch('/me/login-methods/apple', { method: 'POST', body: JSON.stringify({ challengeId, idToken }), signal });
  }

  async loginWithApple(idToken: string, name?: string): Promise<{ token: string; user: any; accessStatus: any }> {
    return this.fetch('/auth/apple', {
      method: 'POST',
      body: JSON.stringify({ idToken, name }),
    }, true);
  }

  async listMessages(_allowOffline = false): Promise<{ messages: SyncaMessage[] }> {
    return this.fetch<{ messages: SyncaMessage[] }>('/messages');
  }

  async listMessageCategories(_allowOffline = false): Promise<{ categories: MessageCategory[] }> {
    return this.fetch<{ categories: MessageCategory[] }>('/message-categories');
  }

  async createMessageCategory(name: string, color: MessageCategoryColor, colorHex?: string | null): Promise<MessageCategory> {
    return this.fetch<MessageCategory>('/message-categories', {
      method: 'POST',
      body: JSON.stringify({ name, color, colorHex }),
    });
  }

  async updateMessageCategory(id: string, payload: Partial<Pick<MessageCategory, 'name' | 'color' | 'colorHex'>>): Promise<MessageCategory> {
    return this.fetch<MessageCategory>(`/message-categories/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(payload),
    });
  }

  async deleteMessageCategory(id: string): Promise<void> {
    await this.fetch(`/message-categories/${id}`, { method: 'DELETE' });
  }

  async reorderMessageCategories(categoryIds: string[]): Promise<void> {
    await this.fetch('/message-categories/order', {
      method: 'PUT',
      body: JSON.stringify({ categoryIds }),
    });
  }

  async sendTextMessage(text: string, categoryId?: string | null): Promise<SyncaMessage> {
    return this.fetch<SyncaMessage>('/messages', {
      method: 'POST',
      body: JSON.stringify({ textContent: text, sourceDevice: 'Web', categoryId: categoryId ?? null }),
    });
  }

  async sendImageMessage(file: File, categoryId?: string | null, options?: UploadOptions): Promise<SyncaMessage> {
    const formData = new FormData();
    formData.append('image', file);
    formData.append('sourceDevice', 'Web');
    if (categoryId) {
      formData.append('categoryId', categoryId);
    }

    const requestToken = this.token;
    const sessionVersion = this.sessionVersion;
    const message = await this.upload('/messages/image', formData, file, options);
    if (requestToken !== this.token || sessionVersion !== this.sessionVersion || options?.signal.aborted) {
      throw new DOMException('Session changed or upload cancelled', 'AbortError');
    }
    this.seedUploadedImage(message, file, requestToken);
    return message;
  }

  private seedUploadedImage(message: SyncaMessage, file: File, requestToken: string | null) {
    if (!requestToken || !message.imageUrl || message.attachmentExpired || message.type !== 'image'
      || !file.type.startsWith('image/') || file.size > UPLOADED_IMAGE_LIMIT_BYTES) return;
    let target: URL;
    try { target = new URL(message.imageUrl, window.location.href); } catch { return; }
    if (target.origin !== window.location.origin || !target.pathname.startsWith('/api/media/')) return;
    const expiresAt = message.attachmentExpiresAt ? Date.parse(message.attachmentExpiresAt) : Infinity;
    if (!(expiresAt > Date.now())) return;
    this.ensureImageCacheSession(requestToken);
    if (this.uploadedImage?.objectURL) URL.revokeObjectURL(this.uploadedImage.objectURL);
    this.uploadedImage = { url: target.href, blob: file, expiresAt: Math.min(expiresAt, Date.now() + IMAGE_CACHE_TTL_MS) };
  }

  private evictImage(key: string) {
    const source = this.imageCache.get(key)?.objectURL;
    if (source) URL.revokeObjectURL(source);
    this.imageCache.delete(key);
  }

  private clearImageSources() {
    for (const key of this.imageCache.keys()) this.evictImage(key);
    if (this.uploadedImage?.objectURL) URL.revokeObjectURL(this.uploadedImage.objectURL);
    this.uploadedImage = null;
  }

  // Reuse the browser's decoded image on a warm category switch. Sources share
  // the existing byte budget, TTL and account lifetime; never persist them.
  cachedImageSource(url: string, attachmentExpiry?: string | null): string | null {
    if (!this.token) return null;
    this.ensureImageCacheSession(this.token);
    let target: URL;
    try { target = new URL(url, window.location.href); } catch { return null; }
    if (target.origin !== window.location.origin || !target.pathname.startsWith('/api/media/')) return null;
    const expiry = attachmentExpiry ? Date.parse(attachmentExpiry) : Infinity;
    const entry = this.uploadedImage?.url === target.href ? this.uploadedImage : this.imageCache.get(target.href);
    if (!entry || !(Math.min(expiry, entry.expiresAt) > Date.now())) return null;
    return entry.objectURL ??= URL.createObjectURL(entry.blob);
  }

  private ensureImageCacheSession(requestToken: string) {
    if (this.imageCacheToken === requestToken) return;
    this.clearImageSources();
    this.uploadedImage = null;
    this.imageCacheToken = requestToken;
  }

  async sendFileMessage(file: File, categoryId?: string | null, options?: UploadOptions): Promise<SyncaMessage> {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('fileName', file.name);
    formData.append('sourceDevice', 'Web');
    if (categoryId) {
      formData.append('categoryId', categoryId);
    }

    return this.upload('/messages/file', formData, file, options);
  }

  private async upload(path: string, form: FormData, file: File, options?: UploadOptions): Promise<SyncaMessage> {
    const size = file.size;
    const uploadID = this.uploadIDs.get(file) ?? crypto.randomUUID();
    this.uploadIDs.set(file, uploadID);
    if (!options) return this.fetch(path, { method: 'POST', body: form, headers: { 'X-Upload-Size': String(size), 'X-Upload-ID': uploadID } });
    const requestToken = this.token;
    const response = await new Promise<Response>((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      this.activeUploads.add(xhr);
      xhr.open('POST', `${BASE_URL}${path}`);
      xhr.timeout = 15 * 60 * 1000;
      if (requestToken) xhr.setRequestHeader('Authorization', `Bearer ${requestToken}`);
      xhr.setRequestHeader('X-Upload-Size', String(size));
      xhr.setRequestHeader('X-Upload-ID', uploadID);
      const abort = () => xhr.abort();
      xhr.onloadend = () => { options.signal.removeEventListener('abort', abort); this.activeUploads.delete(xhr); };
      xhr.upload.onprogress = event => { if (event.lengthComputable) options.onProgress(event.loaded / event.total); };
      xhr.onload = () => resolve(new Response(xhr.responseText, { status: xhr.status }));
      xhr.onerror = () => reject(new Error('Upload failed'));
      xhr.ontimeout = () => reject(new Error('Upload timed out'));
      xhr.onabort = () => reject(new DOMException('Upload cancelled', 'AbortError'));
      if (options.signal.aborted) { this.activeUploads.delete(xhr); reject(new DOMException('Upload cancelled', 'AbortError')); return; }
      options.signal.addEventListener('abort', abort, { once: true });
      xhr.send(form);
    });
    return this.decodeResponse(response, requestToken);
  }

  async getProtectedFileBlob(url: string, options: AttachmentOptions = {}): Promise<Blob> {
    const requestToken = this.token;
    if (!requestToken) throw new DOMException('Session changed', 'AbortError');
    const target = new URL(url, window.location.href);
    if (target.origin !== window.location.origin || !target.pathname.startsWith('/api/media/')) {
      throw new Error('Invalid attachment URL');
    }
    const expiresAt = options.expiresAt ? Date.parse(options.expiresAt) : Infinity;
    if (expiresAt <= Date.now()) throw new StorageError('attachment_expired');
    if (options.signal?.aborted) throw new DOMException('Download cancelled', 'AbortError');
    this.ensureImageCacheSession(requestToken);
    if (this.uploadedImage && this.uploadedImage.expiresAt <= Date.now()) {
      if (this.uploadedImage.objectURL) URL.revokeObjectURL(this.uploadedImage.objectURL);
      this.uploadedImage = null;
    }
    if (options.cacheImage && this.uploadedImage?.url === target.href
      && Math.min(this.uploadedImage.expiresAt, expiresAt) > Date.now()) return this.uploadedImage.blob;
    const cached = this.imageCache.get(target.href);
    if (options.cacheImage && cached && Math.min(cached.expiresAt, expiresAt) > Date.now()) {
      this.imageCache.delete(target.href);
      this.imageCache.set(target.href, cached);
      return cached.blob;
    }
    this.evictImage(target.href);
    const controller = new AbortController();
    const abort = () => controller.abort();
    options.signal?.addEventListener('abort', abort, { once: true });
    this.attachmentRequests.add(controller);
    try {
      const response = await fetch(target.href, {
        headers: { Authorization: `Bearer ${requestToken}` }, signal: controller.signal,
        cache: 'no-store', redirect: 'error',
      });
      if (requestToken !== this.token) throw new DOMException('Session changed', 'AbortError');
      if (!response.ok) return await this.decodeResponse<never>(response, requestToken);
      const blob = await response.blob();
      if (requestToken !== this.token || controller.signal.aborted) throw new DOMException('Download cancelled', 'AbortError');
      if (expiresAt <= Date.now()) throw new StorageError('attachment_expired');
      if (options.cacheImage && blob.type.startsWith('image/') && blob.size <= IMAGE_CACHE_ITEM_LIMIT_BYTES) {
        for (const [key, entry] of this.imageCache) if (entry.expiresAt <= Date.now()) this.evictImage(key);
        let size = [...this.imageCache.values()].reduce((sum, entry) => sum + entry.blob.size, 0);
        while (size + blob.size > IMAGE_CACHE_LIMIT_BYTES && this.imageCache.size) {
          const oldestKey = this.imageCache.keys().next().value!;
          size -= this.imageCache.get(oldestKey)!.blob.size;
          this.evictImage(oldestKey);
        }
        this.imageCache.set(target.href, { blob, expiresAt: Math.min(expiresAt, Date.now() + IMAGE_CACHE_TTL_MS) });
      }
      return blob;
    } finally {
      this.attachmentRequests.delete(controller);
      options.signal?.removeEventListener('abort', abort);
    }
  }

  async openProtectedFile(url: string, expiresAt?: string | null): Promise<string> {
    const blob = await this.getProtectedFileBlob(url, { expiresAt });
    return window.URL.createObjectURL(blob);
  }

  async downloadProtectedFile(url: string, fileName?: string | null, expiresAt?: string | null): Promise<void> {
    const blob = await this.getProtectedFileBlob(url, { expiresAt });
    await saveDownload(blob, fileName || 'attachment');
  }

  async updateMessageText(id: string, textContent: string, expectedUpdatedAt: string): Promise<SyncaMessage> {
    return this.fetch<SyncaMessage>(`/messages/${id}/text`, {
      method: 'PATCH', body: JSON.stringify({ textContent, expectedUpdatedAt }),
    });
  }

  async setMessageCompletion(id: string, isCleared: boolean): Promise<SyncaMessage> {
    return this.fetch<SyncaMessage>(`/messages/${id}/completion`, {
      method: 'PATCH', body: JSON.stringify({ isCleared }),
    });
  }

  async clearMessage(id: string): Promise<void> {
    await this.fetch(`/messages/${id}/clear`, { method: 'PATCH' });
  }

  async updateMessageCategoryAssignment(id: string, categoryId?: string | null): Promise<SyncaMessage> {
    return this.fetch<SyncaMessage>(`/messages/${id}/category`, {
      method: 'PATCH',
      body: JSON.stringify({ categoryId: categoryId ?? null }),
    });
  }

  async clearAllMessages(categoryId?: string | null): Promise<void> {
    await this.fetch('/messages/clear-all', {
      method: 'POST',
      body: JSON.stringify({ categoryId: categoryId ?? null }),
    });
  }

  async deleteMessage(id: string): Promise<void> {
    await this.fetch(`/messages/${id}`, { method: 'DELETE' });
  }

  async deleteCompletedMessages(categoryId?: string | null): Promise<void> {
    await this.fetch('/messages/delete-completed', {
      method: 'POST',
      body: JSON.stringify({ categoryId: categoryId ?? null }),
    });
  }

  // ── Admin ──

  async getAdminOverview(): Promise<any> {
    return this.fetch('/api/admin/overview');
  }

  async getAdminUsers(): Promise<{ users: any[] }> {
    return this.fetch('/api/admin/users');
  }

  async getAdminMessageStats(): Promise<any> {
    return this.fetch('/api/admin/messages/stats');
  }

  async getAdminRevenueStats(): Promise<any> {
    return this.fetch('/api/admin/revenue/stats');
  }

  async submitFeedback(content: string, email: string, images: File[]): Promise<{ ok: boolean }> {
    const body = new FormData();
    body.append('content', content); body.append('email', email); body.append('deviceModel', 'Web');
    images.forEach(image => body.append('images', image));
    return this.fetch('/feedback', { method: 'POST', body });
  }

  async getAdminFeedback(): Promise<{ feedbacks: any[] }> {
    return this.fetch('/api/admin/feedback');
  }

  async deleteAccount(): Promise<{ ok: boolean }> {
    return this.fetch('/me/account', { method: 'DELETE' });
  }

  async getMyProfile(): Promise<ProfileResponse> {
    return this.fetch<ProfileResponse>('/me/access-status');
  }
}

export const api = new APIClient();
