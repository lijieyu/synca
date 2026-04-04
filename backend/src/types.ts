export interface SyncaUser {
    id: string;
    appleUserId: string;
    email?: string | null;
    nickname: string;
    createdAt: string;
    updatedAt: string;
}

export type SyncaAccessPlan = 'trial' | 'free' | 'unlimited';
export type SyncaUnlimitedSource = 'subscription' | 'lifetime' | null;

export interface SyncaAccessStatus {
    plan: SyncaAccessPlan;
    isUnlimited: boolean;
    isTrial: boolean;
    unlimitedSource: SyncaUnlimitedSource;
    trialEndsAt?: string | null;
    daysLeft?: number | null;
    todayUsed: number;
    todayLimit?: number | null;
    dailyResetAt: string;
    purchaseDate?: string | null;
    subscriptionExpiresAt?: string | null;
    storeProductId?: string | null;
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
