# Change Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace high frequency sync polls with account-scoped invalidations and incremental catch-up.
**Architecture:** Authenticated SSE hints, deterministic per-scope state hashes, five-minute anti-entropy checks, reconnect catch-up. Electron owns its transport in the main process; native apps connect while eligible and use APNs in background.
**Tech Stack:** Express/SQLite, React/TypeScript, Electron, Swift URLSession.
**Spec:** docs/superpowers/specs/2026-11-24-change-notifications.md

## Global Constraints
Preserve all existing interactions; Web email disabled; no TF/package release. Reuse current isolated worktree. No new broker dependency. Never put auth tokens in URLs. Never persist deltas as snapshots.

## Review Focus
- Notifications arriving while writes or sync are pending must be retried, not dropped.
- Session changes cancel streams and prevent old responses/cache writes.
- Reconnect and missed notification must repair state including categories, deletions and access expiry.
- Hidden desktop window must still update badge without a renderer timer.
- Network failures must preserve drafts, cursor/search/scroll and last confirmed data.

### Task 1: Backend transport and state
Files: backend/src/syncEvents.ts, app.ts, server.ts, storage.ts; backend/tests/syncEvents.test.ts; scripts/deploy-release.sh.
Interfaces: GET /sync/events authenticated SSE change/heartbeat; GET /sync/state -> messages/categories/access hashes, latestMessage, count. notifySync(userId) coalesces. closeSyncStreams() releases handles.
- [x] Add failing auth/account isolation/state/mutation/cleanup tests; run targeted Vitest.
- [x] Implement bounded authenticated stream, no buffering, immediate catch-up event and heartbeat, all mutations and maintenance invalidation.
- [x] Verify targeted tests and backend build; review single-process deployment and proxy settings.

### Task 2: Web and Electron
Files: web/src/utils/changeNotifications.ts, MessageListView.tsx, api/client.ts; desktop/app/platform.cjs, desktop/ui/snapshot.ts, frontend.patch.
Interfaces: shared notification scheduler coalesces/retries async work; Electron emits refresh hints and updates count independently; Web scope hashes acknowledged only after successful fetch.
- [x] Add failing retry/session/race/browser tests and hidden-window badge test.
- [x] Remove high frequency polls; connect authenticated fetch stream; 5 min summary; incremental desktop and complete snapshot persistence.
- [x] Run browser interaction regression and desktop tests/build.

### Task 3: Native clients and APNs
Files: ios/Synca/Shared/Core/APIClient.swift, SyncManager.swift, lifecycle and AppDelegates; desktop MAS push configuration.
- [x] Test stream parsing/reconnect/state and incremental call sites; inspect existing native tests.
- [x] Replace polling with foreground stream/summary and queued incremental sync; retain first-load snapshot; change APNs callbacks to incremental and correct token lifecycle.
- [x] Validate native compilation/tests, actual installed capability requirements without claiming live APNs delivery.

### Task 4: Review and deploy
- [x] Fresh whole-branch review, resolve significant findings with regression evidence.
- [x] Commit explicit files, deploy backend/Web only using release script, verify assets, health, auth caps, actual SSE via controlled test session and no private record reads.
- [x] Record tested scope and physical-device/APNs limits; clients wait for next package.
