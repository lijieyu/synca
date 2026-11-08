# Image send efficiency before OSS

Scope: client-only optimization, unchanged original bytes and existing API/storage. No production deploy, no OSS migration. Keep future direct-upload compatibility by seeding cache from returned image URL rather than assuming storage paths.

- Native: successful-upload cache seeding fenced by account/session; real upload progress; stream photo reading into sequential uploads if existing order and error behavior can be preserved.
- Web: reuse uploaded File in protected image cache, bounded memory and expiry, never seed failed/stale-account uploads.
- Validation: request-count tests (upload then render requires no image GET), logout/expiry/origin and budget boundaries; native tests and platform builds; Web build. Preview only.
- Deferred: remote thumbnails, compression/original toggles, OSS signed direct upload, network/VPN timing comparison. No claimed end-to-end speedup without measurement.

## Results
- Native original cache seeded before publication, actual upload progress and cancellation registered, PhotosPicker sequential load/upload with captured category. Transfer HTTP tests passed, including cache bytes, foreign/expired rejection, session/cache generation, actual progress/cancellation and existing large file transfer cases.
- Web retains latest successful upload File up to20MB/60s, separate from existing bounded download cache. 46 Vitest checks and Node suite passed; original bytes unchanged. Larger files fall back to existing protected download display.
- macOS and iOS Simulator production configuration builds succeeded. No physical-device/VPN speed comparison or interactive progress QA performed.
- Preview release 20261108T134015Z-b0dd536-preview deployed with working-tree changes; production index checksum unchanged. No push/PR/merge/TF.
- Native disk cache seeding remains synchronous; photo loading already in progress is not interrupted, but cancellation discards its result and prevents remaining uploads.
