export const FREE_DAILY_MESSAGE_LIMIT = 20;
export const DEFAULT_TIMEZONE_OFFSET_SECONDS = 8 * 60 * 60;

export function getUsageWindow(now: Date, offsetSeconds: number) {
    const offsetMs = offsetSeconds * 1000;
    const local = new Date(now.getTime() + offsetMs);
    const startUtcMs = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - offsetMs;
    return {
        start: new Date(startUtcMs).toISOString(),
        end: new Date(startUtcMs + 24 * 60 * 60 * 1000).toISOString(),
    };
}
