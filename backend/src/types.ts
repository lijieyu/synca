export interface SyncaUser {
    id: string;
    appleUserId: string;
    email?: string | null;
    nickname: string;
    createdAt: string;
    updatedAt: string;
}

export interface SyncaMessage {
    id: string;
    userId: string;
    type: 'text' | 'image';
    textContent?: string | null;
    imagePath?: string | null;
    imageUrl?: string | null; // computed: full URL for client
    isCleared: boolean;
    isDeleted: boolean;
    sourceDevice?: string | null;
    createdAt: string;
    updatedAt: string;
}
