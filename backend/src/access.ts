import {
    assignLifetimeUpgradeCode,
    countAvailableLifetimeUpgradeCodes,
    countMessagesCreatedBetween,
    getAssignedLifetimeUpgradeCode,
    getUserAccessFields,
    listUserIapTransactions,
    markAssignedLifetimeUpgradeCodesRedeemed,
    updateUserPurchaseAccess,
} from './store.js';
import { SyncaAccessStatus, SyncaLifetimeUpgradeOffer, SyncaLifetimeUpgradeOfferKind } from './types.js';
import {
    isLifetimeProduct,
    isSupportedProduct,
    isSubscriptionProduct,
    MONTHLY_PRODUCT_ID,
    MONTHLY_TO_LIFETIME_DISCOUNT_LABEL,
    YEARLY_PRODUCT_ID,
    YEARLY_TO_LIFETIME_DISCOUNT_LABEL,
} from './iap.js';

export const FREE_DAILY_MESSAGE_LIMIT = 20;
const TRIAL_LENGTH_DAYS = 7;
const DAILY_RESET_OFFSET_HOURS = 8;

export class DailyLimitError extends Error {
    constructor(public readonly accessStatus: SyncaAccessStatus) {
        super('daily_limit_reached');
    }
}

type UsageWindow = {
    start: string;
    end: string;
};

export async function buildAccessStatus(userId: string, now = new Date()): Promise<SyncaAccessStatus> {
    const user = await getUserAccessFields(userId);
    if (!user) {
        throw new Error('user_not_found');
    }

    const nowIso = now.toISOString();
    const usageWindow = getUsageWindow(now);
    const todayUsed = await countMessagesCreatedBetween(userId, usageWindow.start, usageWindow.end);
    const hasLifetime = Boolean(user.lifetime_purchased_at);
    const hasSubscription = Boolean(user.subscription_expires_at && user.subscription_expires_at > nowIso);
    const isTrial = !hasLifetime && !hasSubscription && Boolean(user.trial_ends_at && user.trial_ends_at > nowIso);

    if (hasLifetime) {
        return {
            plan: 'unlimited',
            isUnlimited: true,
            isTrial: false,
            unlimitedSource: 'lifetime',
            trialEndsAt: user.trial_ends_at,
            daysLeft: daysLeft(user.trial_ends_at, now),
            todayUsed,
            todayLimit: null,
            dailyResetAt: usageWindow.end,
            purchaseDate: user.lifetime_purchased_at ?? user.purchase_date,
            subscriptionExpiresAt: null,
            storeProductId: user.store_product_id,
        };
    }

    if (hasSubscription) {
        return {
            plan: 'unlimited',
            isUnlimited: true,
            isTrial: false,
            unlimitedSource: 'subscription',
            trialEndsAt: user.trial_ends_at,
            daysLeft: daysLeft(user.trial_ends_at, now),
            todayUsed,
            todayLimit: null,
            dailyResetAt: usageWindow.end,
            purchaseDate: user.purchase_date,
            subscriptionExpiresAt: user.subscription_expires_at,
            storeProductId: user.store_product_id,
        };
    }

    if (isTrial) {
        return {
            plan: 'trial',
            isUnlimited: false,
            isTrial: true,
            unlimitedSource: null,
            trialEndsAt: user.trial_ends_at,
            daysLeft: daysLeft(user.trial_ends_at, now),
            todayUsed,
            todayLimit: null,
            dailyResetAt: usageWindow.end,
            purchaseDate: null,
            subscriptionExpiresAt: null,
            storeProductId: user.store_product_id,
        };
    }

    return {
        plan: 'free',
        isUnlimited: false,
        isTrial: false,
        unlimitedSource: null,
        trialEndsAt: user.trial_ends_at,
        daysLeft: 0,
        todayUsed,
        todayLimit: FREE_DAILY_MESSAGE_LIMIT,
        dailyResetAt: usageWindow.end,
        purchaseDate: null,
        subscriptionExpiresAt: null,
        storeProductId: user.store_product_id,
    };
}

export async function assertCanCreateMessage(userId: string, now = new Date()): Promise<SyncaAccessStatus> {
    const status = await buildAccessStatus(userId, now);
    if (!status.isUnlimited && !status.isTrial && status.todayUsed >= FREE_DAILY_MESSAGE_LIMIT) {
        throw new DailyLimitError(status);
    }
    return status;
}

export function buildTrialWindow(now = new Date()): { trialStartedAt: string; trialEndsAt: string } {
    const trialStartedAt = now.toISOString();
    const trialEndsAt = new Date(now.getTime() + TRIAL_LENGTH_DAYS * 24 * 60 * 60 * 1000).toISOString();
    return { trialStartedAt, trialEndsAt };
}

export async function reconcilePurchaseAccess(userId: string, now = new Date()): Promise<void> {
    const transactions = await listUserIapTransactions(userId);
    const nowMs = now.getTime();

    const activeTransactions = transactions.filter((transaction) => isSupportedProduct(transaction.product_id));

    const lifetimeTransaction = activeTransactions
        .filter((transaction) => isLifetimeProduct(transaction.product_id) && !transaction.revocation_date)
        .sort(comparePurchaseDateAsc)[0];

    const activeSubscription = activeTransactions
        .filter((transaction) => {
            if (!isSubscriptionProduct(transaction.product_id)) return false;
            if (transaction.revocation_date) return false;
            if (transaction.is_upgraded === 1) return false;
            if (!transaction.expires_at) return false;
            return new Date(transaction.expires_at).getTime() > nowMs;
        })
        .sort(compareSubscriptionDesc)[0];

    await updateUserPurchaseAccess({
        userId,
        purchaseDate: lifetimeTransaction?.purchase_date ?? activeSubscription?.original_purchase_date ?? activeSubscription?.purchase_date ?? null,
        lifetimePurchasedAt: lifetimeTransaction?.purchase_date ?? null,
        subscriptionExpiresAt: activeSubscription?.expires_at ?? null,
        storeProductId: lifetimeTransaction?.product_id ?? activeSubscription?.product_id ?? null,
        now: now.toISOString(),
    });

    if (lifetimeTransaction) {
        await markAssignedLifetimeUpgradeCodesRedeemed(userId, now.toISOString());
    }
}

export async function buildLifetimeUpgradeOffer(userId: string, status: SyncaAccessStatus): Promise<SyncaLifetimeUpgradeOffer | null> {
    if (status.unlimitedSource != 'subscription') {
        return null;
    }

    const kind = lifetimeUpgradeKindForProduct(status.storeProductId);
    if (!kind) {
        return null;
    }

    let assignedCode = await getAssignedLifetimeUpgradeCode(userId, kind);
    let availableCount = 0;

    if (!assignedCode) {
        availableCount = await countAvailableLifetimeUpgradeCodes(kind);
        if (availableCount > 0) {
            assignedCode = await assignLifetimeUpgradeCode(userId, kind, new Date().toISOString());
            availableCount = assignedCode ? 1 : availableCount;
        }
    }

    return {
        kind,
        discountedPriceLabel: discountedPriceLabelForKind(kind),
        isCodeAvailable: Boolean(assignedCode || availableCount > 0),
        code: assignedCode?.code ?? null,
    };
}

function daysLeft(trialEndsAt: string | null, now: Date): number | null {
    if (!trialEndsAt) return null;
    const end = new Date(trialEndsAt);
    const diff = end.getTime() - now.getTime();
    if (diff <= 0) return 0;
    return Math.max(1, Math.ceil(diff / (24 * 60 * 60 * 1000)));
}

function getUsageWindow(now: Date): UsageWindow {
    const offsetMs = DAILY_RESET_OFFSET_HOURS * 60 * 60 * 1000;
    const local = new Date(now.getTime() + offsetMs);
    const startUtcMs = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - offsetMs;
    const endUtcMs = startUtcMs + 24 * 60 * 60 * 1000;
    return {
        start: new Date(startUtcMs).toISOString(),
        end: new Date(endUtcMs).toISOString(),
    };
}

function comparePurchaseDateAsc(a: { purchase_date: string | null }, b: { purchase_date: string | null }): number {
    return (new Date(a.purchase_date ?? 0).getTime()) - (new Date(b.purchase_date ?? 0).getTime());
}

function compareSubscriptionDesc(
    a: { expires_at: string | null; purchase_date: string | null },
    b: { expires_at: string | null; purchase_date: string | null }
): number {
    const expiryDiff = new Date(b.expires_at ?? 0).getTime() - new Date(a.expires_at ?? 0).getTime();
    if (expiryDiff !== 0) return expiryDiff;
    return new Date(b.purchase_date ?? 0).getTime() - new Date(a.purchase_date ?? 0).getTime();
}

function lifetimeUpgradeKindForProduct(productId: string | null | undefined): SyncaLifetimeUpgradeOfferKind | null {
    if (productId === MONTHLY_PRODUCT_ID) return 'monthly_to_lifetime';
    if (productId === YEARLY_PRODUCT_ID) return 'yearly_to_lifetime';
    return null;
}

function discountedPriceLabelForKind(kind: SyncaLifetimeUpgradeOfferKind): string {
    return kind === 'monthly_to_lifetime'
        ? MONTHLY_TO_LIFETIME_DISCOUNT_LABEL
        : YEARLY_TO_LIFETIME_DISCOUNT_LABEL;
}
