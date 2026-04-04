import { Generated } from 'kysely';

export interface UsersTable {
    id: string;
    apple_user_id: string;
    email: string | null;
    nickname: string;
    trial_started_at: string | null;
    trial_ends_at: string | null;
    purchase_date: string | null;
    subscription_expires_at: string | null;
    lifetime_purchased_at: string | null;
    store_product_id: string | null;
    created_at: string;
    updated_at: string;
}

export interface MessagesTable {
    id: string;
    user_id: string;
    type: string; // 'text' | 'image'
    text_content: string | null;
    image_path: string | null;
    is_cleared: number; // 0 | 1
    is_deleted: number; // 0 | 1
    source_device: string | null;
    created_at: string;
    updated_at: string;
}

export interface SessionsTable {
    token: string;
    user_id: string;
    device_id: string | null;
    created_at: string;
}

export interface DevicePushTokensTable {
    id: string;
    user_id: string;
    platform: string; // 'ios' | 'macos'
    token: string;
    apns_environment: string; // 'production' | 'sandbox'
    topic: string | null;
    is_active: number; // 0 | 1
    last_error: string | null;
    last_sent_at: string | null;
    created_at: string;
    updated_at: string;
}

export interface IapTransactionsTable {
    transaction_id: string;
    original_transaction_id: string | null;
    user_id: string;
    product_id: string;
    environment: string;
    type: string | null;
    app_account_token: string | null;
    purchase_date: string | null;
    original_purchase_date: string | null;
    expires_at: string | null;
    revocation_date: string | null;
    is_upgraded: number;
    signed_transaction_info: string;
    created_at: string;
    updated_at: string;
}

export interface FeedbacksTable {
    id: string;
    user_id: string;
    content: string;
    email: string;
    image_paths: string | null;
    created_at: string;
    updated_at: string;
}

export interface Database {
    users: UsersTable;
    messages: MessagesTable;
    sessions: SessionsTable;
    device_push_tokens: DevicePushTokensTable;
    iap_transactions: IapTransactionsTable;
    feedbacks: FeedbacksTable;
}
