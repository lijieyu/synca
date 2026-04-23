export interface SyncaUser {
    id: string;
    appleUserId: string;
    email?: string | null;
    nickname: string;
    createdAt: string;
    updatedAt: string;
    isAdmin: boolean;
}

export type SyncaAccessPlan = 'trial' | 'free' | 'unlimited';
export type SyncaUnlimitedSource = 'subscription' | 'lifetime' | null;
export type SyncaLifetimeUpgradeOfferKind = 'monthly_to_lifetime' | 'yearly_to_lifetime';

export interface SyncaLifetimeUpgradeOffer {
    kind: SyncaLifetimeUpgradeOfferKind;
    discountedPriceLabel: string;
    isCodeAvailable: boolean;
    code?: string | null;
}

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
    lifetimeUpgradeOffer?: SyncaLifetimeUpgradeOffer | null;
}

export interface SyncaMessage {
    id: string;
    userId: string;
    type: 'text' | 'image' | 'file';
    textContent?: string | null;
    imagePath?: string | null;
    imageUrl?: string | null; // computed: full URL for client
    filePath?: string | null;
    fileUrl?: string | null;
    fileName?: string | null;
    fileSize?: number | null;
    fileMimeType?: string | null;
    categoryId?: string | null;
    categoryName?: string | null;
    categoryColor?: string | null;
    categoryIsDefault?: boolean;
    isCleared: boolean;
    isDeleted: boolean;
    sourceDevice?: string | null;
    createdAt: string;
    updatedAt: string;
}

export type SyncaMessageCategoryColor =
    | 'sky'
    | 'mint'
    | 'amber'
    | 'coral'
    | 'violet'
    | 'slate'
    | 'rose'
    | 'ocean';

export interface SyncaMessageCategory {
    id: string;
    userId: string;
    name: string;
    color: SyncaMessageCategoryColor;
    isDefault: boolean;
    createdAt: string;
    updatedAt: string;
}
