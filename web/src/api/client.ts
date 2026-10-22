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
  plan: 'free' | 'unlimited';
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
const IMAGE_CACHE_TTL_MS = 60 * 1000;

class APIClient {
  constructor() {
    if (typeof window !== 'undefined' && 'caches' in window) void caches.delete(ATTACHMENT_CACHE_NAME).catch(() => {});
  }
  private readonly imageCache = new Map<string, { blob: Blob; expiresAt: number }>();
  private imageCacheToken: string | null = null;
  private readonly attachmentRequests = new Set<AbortController>();
  private readonly activeUploads = new Set<XMLHttpRequest>();

  // Never persist protected attachments: an old browser cache must not bypass expiry or sign-out.
  resetSession() {
    this.imageCache.clear();
    this.imageCacheToken = this.token;
    this.attachmentRequests.forEach(controller => controller.abort());
    this.attachmentRequests.clear();
    this.activeUploads.forEach(xhr => xhr.abort());
    this.activeUploads.clear();
    if ('caches' in window) void caches.delete(ATTACHMENT_CACHE_NAME).catch(() => {});
  }

  private readonly uploadIDs = new WeakMap<File, string>();
  private get token(): string | null {
    return localStorage.getItem('authToken');
  }

  private async fetch<T>(path: string, options: RequestInit = {}): Promise<T> {
    const requestToken = this.token;
    const headers: Record<string, string> = {
      ...(!options.body || typeof options.body === 'string' ? { 'Content-Type': 'application/json' } : {}),
      ...(options.headers as Record<string, string>),
    };

    if (requestToken) {
      headers['Authorization'] = `Bearer ${requestToken}`;
    }

    const response = await fetch(`${BASE_URL}${path}`, {
      ...options,
      headers,
    });

    return this.decodeResponse<T>(response, requestToken);
  }

  private async decodeResponse<T>(response: Response, requestToken: string | null): Promise<T> {
    if (requestToken !== this.token) throw new DOMException('Session changed', 'AbortError');

    if (response.status === 401) {
      localStorage.removeItem('authToken');
      window.location.reload();
      throw new Error('Unauthorized');
    }

    if (!response.ok) {
      const errorText = await response.text();
      if (requestToken !== this.token) throw new DOMException('Session changed', 'AbortError');
      try {
        const errorJson = JSON.parse(errorText);
        if (['file_upload_requires_paid', 'storage_limit_reached', 'attachment_expired', 'file_too_large'].includes(errorJson.error)) throw new StorageError(errorJson.error);
        if (response.status === 403 && errorJson.error === 'daily_limit_reached') {
          throw new DailyLimitError();
        }
      } catch (e) {
        if (e instanceof DailyLimitError || e instanceof StorageError) throw e;
      }
      throw new Error(`API Error: ${response.status} ${errorText}`);
    }

    const result = await response.json();
    if (requestToken !== this.token) throw new DOMException('Session changed', 'AbortError');
    return result;
  }

  async loginWithApple(idToken: string, name?: string): Promise<{ token: string; user: any; accessStatus: any }> {
    return this.fetch('/auth/apple', {
      method: 'POST',
      body: JSON.stringify({ idToken, name }),
    });
  }

  async listMessages(): Promise<{ messages: SyncaMessage[] }> {
    return this.fetch<{ messages: SyncaMessage[] }>('/messages');
  }

  async listMessageCategories(): Promise<{ categories: MessageCategory[] }> {
    return this.fetch<{ categories: MessageCategory[] }>('/message-categories');
  }

  async createMessageCategory(name: string, color: MessageCategoryColor): Promise<MessageCategory> {
    return this.fetch<MessageCategory>('/message-categories', {
      method: 'POST',
      body: JSON.stringify({ name, color }),
    });
  }

  async updateMessageCategory(id: string, payload: Partial<Pick<MessageCategory, 'name' | 'color'>>): Promise<MessageCategory> {
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

    return this.upload('/messages/image', formData, file, options);
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
    if (this.imageCacheToken !== requestToken) { this.imageCache.clear(); this.imageCacheToken = requestToken; }
    const cached = this.imageCache.get(target.href);
    if (options.cacheImage && cached && Math.min(cached.expiresAt, expiresAt) > Date.now()) {
      this.imageCache.delete(target.href);
      this.imageCache.set(target.href, cached);
      return cached.blob;
    }
    this.imageCache.delete(target.href);
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
        for (const [key, entry] of this.imageCache) if (entry.expiresAt <= Date.now()) this.imageCache.delete(key);
        let size = [...this.imageCache.values()].reduce((sum, entry) => sum + entry.blob.size, 0);
        while (size + blob.size > IMAGE_CACHE_LIMIT_BYTES && this.imageCache.size) {
          const oldestKey = this.imageCache.keys().next().value!;
          size -= this.imageCache.get(oldestKey)!.blob.size;
          this.imageCache.delete(oldestKey);
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
    const objectUrl = window.URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = objectUrl;
    anchor.download = fileName || 'attachment';
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    // Give the browser time to start consuming a large download before releasing its object URL.
    window.setTimeout(() => window.URL.revokeObjectURL(objectUrl), 60_000);
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

  async getAdminFeedback(): Promise<{ feedbacks: any[] }> {
    return this.fetch('/api/admin/feedback');
  }

  async getMyProfile(): Promise<ProfileResponse> {
    return this.fetch<ProfileResponse>('/me/access-status');
  }
}

export const api = new APIClient();
