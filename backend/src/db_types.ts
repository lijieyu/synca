import { Generated } from 'kysely';

export interface UsersTable {
    id: string;
    apple_user_id: string;
    email: string | null;
    nickname: string;
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

export interface Database {
    users: UsersTable;
    messages: MessagesTable;
    sessions: SessionsTable;
    device_push_tokens: DevicePushTokensTable;
}
