const BASE_URL = '';

export interface SyncaMessage {
  id: string;
  sourceDevice: string;
  textContent: string | null;
  imagePath: string | null;
  imageUrl: string | null;
  type: 'text' | 'image';
  isCleared: boolean;
  isDeleted: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface AuthResponse {
  token: string;
  user: {
    id: string;
    email: string;
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

  async sendTextMessage(text: string): Promise<SyncaMessage> {
    return this.fetch<SyncaMessage>('/messages', {
      method: 'POST',
      body: JSON.stringify({ textContent: text, sourceDevice: 'Web' }),
    });
  }

  async sendImageMessage(file: File): Promise<SyncaMessage> {
    const formData = new FormData();
    formData.append('image', file);
    formData.append('sourceDevice', 'Web');

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
      throw new Error(`Failed to upload: ${response.statusText}`);
    }

    return response.json();
  }

  async clearMessage(id: string): Promise<void> {
    await this.fetch(`/messages/${id}/clear`, { method: 'PATCH' });
  }

  async clearAllMessages(): Promise<void> {
    await this.fetch('/messages/clear-all', { method: 'POST' });
  }

  async deleteMessage(id: string): Promise<void> {
    await this.fetch(`/messages/${id}`, { method: 'DELETE' });
  }

  async deleteCompletedMessages(): Promise<void> {
    await this.fetch('/messages/delete-completed', { method: 'POST' });
  }
}

export const api = new APIClient();
