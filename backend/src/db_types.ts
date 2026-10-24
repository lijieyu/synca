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
    is_admin: number; // 0 | 1
    timezone_offset_seconds: number | null;
    created_at: string;
    updated_at: string;
}

export interface MessagesTable {
    attachment_expires_at: string | null;
    attachment_purged: Generated<number>;
    id: string;
    user_id: string;
    type: string; // 'text' | 'image' | 'file'
    text_content: string | null;
    image_path: string | null;
    file_path: string | null;
    file_name: string | null;
    file_size: number | null;
    file_mime_type: string | null;
    category_id: string | null;
    is_cleared: number; // 0 | 1
    is_deleted: number; // 0 | 1
    source_device: string | null;
    created_at: string;
    updated_at: string;
}

export interface MessageCategoriesTable {
    id: string;
    user_id: string;
    name: string;
    color: string;
    is_default: number; // 0 | 1
    sort_order: number;
    created_at: string;
    updated_at: string;
}

export interface MessageUsageEventsTable {
    message_id: string;
    user_id: string;
    created_at: string;
    recorded_at: string;
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
    device_model: string | null;
    os_version: string | null;
    app_version: string | null;
    created_at: string;
    updated_at: string;
}

export interface LifetimeUpgradeOfferCodesTable {
    id: string;
    offer_kind: string; // 'monthly_to_lifetime' | 'yearly_to_lifetime'
    code: string;
    assigned_user_id: string | null;
    assigned_at: string | null;
    redeemed_at: string | null;
    is_active: number; // 0 | 1
    created_at: string;
    updated_at: string;
}

export interface AIConnectionsTable {
    id: string; user_id: string; name: string; token_hash: string; scopes: string;
    created_at: string; expires_at: string; revoked_at: string | null; last_used_at: string | null; client_id: string | null;
}
export interface AIOperationsTable {
    id: string; user_id: string; connection_id: string; kind: string; payload: string;
    result: string | null; created_at: string; expires_at: string | null; status: string; request_key: string | null;
}
export interface AIOAuthClientsTable { id: string; metadata: string; created_at: string }
export interface AIOAuthRequestsTable {
    id: string; client_id: string; redirect_uri: string; challenge: string; state: string | null;
    scopes: string; expires_at: string; code_hash: string | null; connection_id: string | null; resource: string;
}
export interface Database {
    ai_connections: AIConnectionsTable;
    ai_operations: AIOperationsTable;
    ai_oauth_clients: AIOAuthClientsTable;
    ai_oauth_requests: AIOAuthRequestsTable;
    users: UsersTable;
    messages: MessagesTable;
    message_categories: MessageCategoriesTable;
    message_usage_events: MessageUsageEventsTable;
    sessions: SessionsTable;
    device_push_tokens: DevicePushTokensTable;
    iap_transactions: IapTransactionsTable;
    feedbacks: FeedbacksTable;
    lifetime_upgrade_offer_codes: LifetimeUpgradeOfferCodesTable;
}
