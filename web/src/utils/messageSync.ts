import type { SyncaMessage } from '../api/client';

// The existing API filters with `updated_at > since`. Re-read the boundary second
// so independent writes sharing a timestamp are not missed; HTTP ETag removes
// unchanged overlap payloads. Never advance this watermark from a local write.
const OVERLAP_MS = 1000;
const EMPTY_CHECKPOINT = '1970-01-01T00:00:00.000Z';
export function messageChangesSince(checkpoint: string): string {
  return new Date(Math.max(0, Date.parse(checkpoint) - OVERLAP_MS)).toISOString();
}
export function nextMessageCheckpoint(previous: string | null, changes: SyncaMessage[]): string {
  let latest = Date.parse(previous ?? EMPTY_CHECKPOINT);
  for (const message of changes) {
    const revision = Date.parse(message.updatedAt);
    if (!Number.isFinite(revision)) throw new Error('Invalid message revision');
    latest = Math.max(latest, revision);
  }
  return new Date(latest).toISOString();
}
export function mergeMessageChanges(current: SyncaMessage[], changes: SyncaMessage[]): SyncaMessage[] {
  const records = new Map(current.map(message => [message.id, message]));
  let changed = false;
  for (const incoming of changes) {
    const previous = records.get(incoming.id);
    if (previous && Date.parse(incoming.updatedAt) < Date.parse(previous.updatedAt)) continue;
    if (incoming.isDeleted) { changed = records.delete(incoming.id) || changed; continue; }
    if (!previous || JSON.stringify(previous) !== JSON.stringify(incoming)) {
      records.set(incoming.id, incoming); changed = true;
    }
  }
  return changed ? [...records.values()] : current;
}
