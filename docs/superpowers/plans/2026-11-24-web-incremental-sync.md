# Web incremental synchronization implementation plan

> Execute inline with superpowers:executing-plans; review once after affected tests pass.

**Goal:** Stop recurring full-record downloads in Web without losing automatic cross-device changes. Client releases are deferred by the owner.

**Architecture:** Initial Web load gets the live list. Subsequent automatic, foreground and manual sync use the existing authenticated `/messages?since=` endpoint, merge revisions and deletion tombstones, and advance a server-record-derived checkpoint only after the complete accepted response. Retain a timestamp overlap to cover same-millisecond changes and conditionally revalidate the overlapping payload with ETag, so unchanged rows are not repeatedly transferred. Category lists remain authoritative (small, including removal/order), and active editor/search/draft/scroll behavior stays intact. Never infer the sync cursor from a local write. Electron stays on its existing snapshot-aware path until its coordinated next release.

**Scope:** Deploy the Web change and its required backwards-compatible server cursor protection. No client packaging, APNs switch or new real-time infrastructure this turn. Keep production Web email login disabled.

- [x] Add failing tests for delta merge, deletion, unchanged data, same-timestamp boundaries, empty initial list, failed/stale sync, category metadata, session isolation and conditional responses.
- [x] Add isolated Web delta reader/state helpers and integrate with existing guarded fetchData. Preserve Electron list API/patch and snapshot behavior.
- [x] Run focused unit/browser regressions, shared build compatibility and independent review. Validate network response volume using synthetic records, not private user records.
- [ ] Commit and deploy Web plus the required cursor protection; verify live HTML/assets and email capability. Do not merge to main or trigger TF in this task.

## Next client release and follow-up

- iOS/native Mac: remove periodic 30-second full refresh; verify incrementals, category deletion/reorder, attachment expiry, APNs callbacks and foreground catch-up.
- Electron Mac/Windows: apply incrementals with persisted complete snapshots, retain background badge refresh until a replacement is verified; do not write delta responses as complete snapshots.
- APNs: the initial isolated MAS verification build disabled push; the production MAS mode deliberately retained that restriction (`push: !isolated && !mas`). Production docs state native APNs was not enabled. Complete entitlement/profile/topic/registration/device-delivery validation rather than just flipping the flag.
- Following this traffic fix: authenticated change notification channel + delta catch-up, reconnect/foreground/wake recovery, desktop main-process ownership for hidden windows; APNs for best-effort iOS background wake. Measure bytes, requests and convergence delay; existing installed clients continue old polling until updated.

## Review and decisions

- Final review: one fresh read-only review. Two important issues reproduced before correction.
- Ruling: existing per-row timestamps can miss delayed writes / clock rollback once periodic full refresh is removed. Add an account-wide monotonic timestamp expression evaluated inside each message write, including AI writes, with an indexed account/revision lookup. Deploy this required server protection before Web. Existing client API shapes remain unchanged. Cost: a small indexed lookup per write and a brief API restart during deployment.
- Fixed: timestamp regression reproduced in an isolated SQLite test (RED), then account isolation, late insert, backwards clock update and bulk update pass (GREEN). The full backend suite passes 194 tests; two existing opt-in mail integration tests are skipped, no email flow changed.
- Fixed: remote category deletion reproduced in the production browser fixture (RED); current/default-send selection now falls back, both unsent drafts are retained, and caret is restored (GREEN).
- Final minor (deferred): an accepted HTTP 304 still traverses the local record map. This does not send record bodies; skip redundant merging in the later all-client synchronization pass.
- Review boundaries: production authenticated ETag traffic and APNs delivery are not claimed from local tests. Validate live release assets and public capability endpoints after deployment; real billing impact requires subsequent traffic observation. No client build or TF is included.
