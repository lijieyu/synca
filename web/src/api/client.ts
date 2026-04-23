const BASE_URL = '';

export interface SyncaMessage {
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

class APIClient {
  private get token(): string | null {
    return localStorage.getItem('authToken');
  }

  private async fetch<T>(path: string, options: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = {
      ...(!options.body || typeof options.body === 'string' ? { 'Content-Type': 'application/json' } : {}),
      ...(options.headers as Record<string, string>),
    };

    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const response = await fetch(`${BASE_URL}${path}`, {
      ...options,
      headers,
    });

    if (response.status === 401) {
      localStorage.removeItem('authToken');
      window.location.reload();
      throw new Error('Unauthorized');
    }

    if (!response.ok) {
      const errorText = await response.text();
      try {
        const errorJson = JSON.parse(errorText);
        if (response.status === 403 && errorJson.error === 'daily_limit_reached') {
          throw new DailyLimitError();
        }
      } catch (e) {
        if (e instanceof DailyLimitError) throw e;
      }
      throw new Error(`API Error: ${response.status} ${errorText}`);
    }

    return response.json();
  }

  async loginWithApple(idToken: string): Promise<AuthResponse> {
    return this.fetch<AuthResponse>('/auth/apple', {
      method: 'POST',
      body: JSON.stringify({ idToken }),
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

  async sendTextMessage(text: string, categoryId?: string | null): Promise<SyncaMessage> {
    return this.fetch<SyncaMessage>('/messages', {
      method: 'POST',
      body: JSON.stringify({ textContent: text, sourceDevice: 'Web', categoryId: categoryId ?? null }),
    });
  }

  async sendImageMessage(file: File, categoryId?: string | null): Promise<SyncaMessage> {
    const formData = new FormData();
    formData.append('image', file);
    formData.append('sourceDevice', 'Web');
    if (categoryId) {
      formData.append('categoryId', categoryId);
    }

    const headers: Record<string, string> = {};
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const response = await fetch(`${BASE_URL}/messages/image`, {
      method: 'POST',
      body: formData,
      headers,
    });

    if (!response.ok) {
      const errorText = await response.text();
      try {
        const errorJson = JSON.parse(errorText);
        if (response.status === 403 && errorJson.error === 'daily_limit_reached') {
          throw new DailyLimitError();
        }
      } catch (e) {
        if (e instanceof DailyLimitError) throw e;
      }
      throw new Error(`Failed to upload: ${response.statusText}`);
    }

    return response.json();
  }

  async sendFileMessage(file: File, categoryId?: string | null): Promise<SyncaMessage> {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('fileName', file.name);
    formData.append('sourceDevice', 'Web');
    if (categoryId) {
      formData.append('categoryId', categoryId);
    }

    const headers: Record<string, string> = {};
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const response = await fetch(`${BASE_URL}/messages/file`, {
      method: 'POST',
      body: formData,
      headers,
    });

    if (!response.ok) {
      const errorText = await response.text();
      try {
        const errorJson = JSON.parse(errorText);
        if (response.status === 403 && errorJson.error === 'daily_limit_reached') {
          throw new DailyLimitError();
        }
      } catch (e) {
        if (e instanceof DailyLimitError) throw e;
      }
      throw new Error(`Failed to upload file: ${response.statusText}`);
    }

    return response.json();
  }

  async downloadProtectedFile(url: string, fileName?: string | null): Promise<void> {
    const headers: Record<string, string> = {};
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const response = await fetch(url, { headers });
    if (!response.ok) {
      throw new Error(`Failed to download file: ${response.statusText}`);
    }

    const blob = await response.blob();
    const objectUrl = window.URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = objectUrl;
    anchor.download = fileName || 'attachment';
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.URL.revokeObjectURL(objectUrl);
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
