# Backend reliability repair

Approved scope: fix the four operational issues discussed in this chat with small, backward-compatible changes. Execute inline using test-first verification.

- Reproduce invalid OAuth redirect URL producing 500; reject malformed URLs as 400 while preserving HTTPS/loopback restrictions.
- Reproduce HTTP/2 transient stream cancellation; reuse sessions per APNs environment, retire on GOAWAY/error/idle, bound background retry to one fresh connection. Never retry permanent token errors or ambiguous alert failures.
- Add timestamped structured error events with generated request IDs and safe route/error codes; omit private payloads, tokens, and raw URLs.
- Verify interrupted-upload reservation/file cleanup and idempotent retry; handle aborted requests without treating expected cancellation as an internal failure.
- Run backend regression suite and build; review diff; commit repair. Deploy backend using existing backup/rollback script after verifying production code has not drifted. Verify public health/auth/invalid URL and process stability. APNs on-device delivery remains separate UAT.

## Verification

- Reproduced invalid OAuth registration returning500 before fix; now400.
- Reproduced failed background retry before fix; bounded retry and session reuse now covered.
- Independent review found 415 parser status regression and shared-session destruction on stream timeout; fixed with regression tests, including a concurrent alert finishing after the background stream times out.
- Full suite:119 tests passed across9 files; TypeScript build passed. Existing Node25 socket flakiness also reproduced on unchanged base; isolated cases and final complete suite passed.
- Actual multipart disconnection releases reservation; retry reuses upload ID without duplicate records.
- New JSON operational events: apns.accepted, apns.retry, apns.failed, upload.cancelled, http.error, http.server_error, ai.operation_failed, server.shutdown. Event timestamps are UTC; daily reports must convert to Asia/Shanghai. Logs omit payloads, raw URLs, auth headers and device tokens. Current-stream cancellation root cause still requires post-release observation; Apple acceptance does not prove device delivery.
