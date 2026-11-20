# Desktop Email Login Implementation Plan

**Goal:** Implement the approved centered login in Web/Electron, email OTP login with automatic signup, settings-only bidirectional binding, and stable email-help expansion.
**Architecture:** Shared React components; existing bearer sessions and user UUID remain authoritative. Nullable legacy Apple identity plus unique verified email identities. SQLite-backed one-use challenges and throttles. Backend-only Aliyun DirectMail transport.
**Tech Stack:** React/TypeScript, Express, Kysely/SQLite, Node crypto, existing Electron package.
**Spec:** docs/superpowers/specs/2026-11-21-desktop-login-design.md

## Global Constraints
- Keep approved copy and paths. No signup confirmation, login-time binding prompts, extra slogans, or mobile-native changes.
- Web and Electron share components. Existing Apple accounts, data, plans, session isolation and native Apple login remain compatible.
- No real mail without configured service; no simulated provider in deployed product. Credentials never enter client bundles/logs.
- Work in the current isolated worktree; save local commits, no push/merge; production service rollout requires verified configuration and migration backup.

## API Contract
- POST /auth/email/code {email,locale?} -> {challengeId,expiresAt,resendAt}, ISO timestamps.
- POST /auth/email/verify {challengeId,code,deviceId?} -> existing {token,user,accessStatus}.
- GET /me/login-methods -> {apple:boolean,email:string|null} (bearer required).
- POST /me/login-methods/email/code {email,locale?} -> same challenge (bearer required).
- POST /me/login-methods/email/verify {challengeId,code} -> login methods.
- POST /me/login-methods/apple/challenge -> {challengeId,nonce,expiresAt} (bearer required).
- POST /me/login-methods/apple {challengeId,idToken} -> login methods (bearer required).
- Existing POST /auth/apple stays compatible. Binding Apple verifies nonce and subject with Apple keys and same authenticated user/session, never reuses login as binding.
- Error JSON {error,retryAfter?}; 400 invalid_payload/invalid_email/invalid_code/code_expired/code_attempts_exceeded/apple_auth_failed; 409 email_in_use/apple_in_use/email_already_bound/apple_already_bound; 429 rate_limited; 503 email_unavailable/email_send_failed; 401 unauthorized only for invalid session.

## Review Focus
- Resends invalidate old codes only when new delivery is accepted; invalid/expired/reused/wrong-purpose/wrong-session challenges never authenticate.
- Concurrent verification must neither duplicate accounts nor bind to multiple users; existing data and entitlements stay on one UUID.
- Email profile text is not an identity. Never automatically merge Apple/email users or grant admin from matching email.
- Abort/cancel/unmount/account switch cannot log into or mutate a different session. Apple cancel/error returns to usable view.
- Help expansion never moves the heading/input/buttons; minimum desktop, dark mode, keyboard and long addresses stay usable.

## Task 1: Backend identity and delivery
- [x] Add API tests for signup/relogin, Apple-email and email-Apple binding, profile-only address, account conflict, nonce/session/purpose, resend/expiry/reuse, attempts and throttling. Initial baseline was blocked by missing dependencies; review regression tests were explicitly observed failing before fixes and passing afterward.
- [x] Add safe nullable Apple migration, email identities, challenge/rate tables and deletion cleanup. Validate migration with populated old schema and rerun idempotence.
- [x] Implement DirectMail signing and configurable transport with timeouts; inject mail only in tests, no production test endpoint. Implement API contract and transactionally consume proofs.
- [x] Run targeted auth tests, backend full suite and TypeScript build.

## Task 2: Shared desktop UI
- [x] Add approved LoginView, reusable EmailVerification form and Apple authorization helper, settings LoginMethods; adapt api client and locale files only as necessary.
- [x] Preserve all approved copy; render email help below a fixed-height/top-anchored form so toggling does not recenter content.
- [x] Check browser flows with mocked transport, keyboard/error/cancel, help geometry, 640x500 and desktop light/dark. Build Web and Electron renderer.

## Task 3: Integration and delivery
- [x] Real local API integration in an isolated test DB with captured test delivery, two sessions, existing user records and account deletion; no real user data.
- [x] Independently review auth changes; resolve security/correctness findings, rerun affected tests.
- [x] Build and test Mac Electron only against an isolated compatible local backend.
- [ ] Install on Mini and publish product preview: blocked until DirectMail configuration and live delivery are verified. Current installed app and live service remain unchanged.
- [x] Document necessary DirectMail environment and delivery verification; report configuration gaps precisely. Save local commit(s).

## Verification and remaining delivery boundary (2026-11-21)

- Backend full suite: 189 passed, 2 opt-in browser cases skipped; those two separately passed with built Web and the packaged Electron binary against real isolated Express/SQLite. External Apple identity verification and mail delivery are test doubles in that integration suite.
- Web: 115 Vitest cases; 3 Node-runner draft/locale checks. Backend, Web, shared Electron renderer and macOS arm64 package built successfully.
- Browser visual checks cover light/dark, ordinary desktop, 640×500, help expansion, inline errors, cancellation, settings navigation and both binding forms. Packaged Electron additionally checks Apple logo assets load and the minimum-window document does not overflow vertically.
- Independent authentication review completed. Fixed concurrent Apple-login profile overwrite, shared-IP Apple-binding quota exhaustion, and documented the requirement to remove historical automatic-admin bootstrap from any rollback backend. Added regression tests for these paths.
- Packaged Electron opened the real Apple authorization window at `https://appleid.apple.com`; no real identity was submitted, so live callback/account binding still requires provider acceptance testing.
- Final account-deletion regression also clears pending login proofs for the verified email, preventing a pre-deletion code from creating another account afterward.
- Aliyun setup is authorized but inaccessible: this chat reports local browser access unavailable, native Chrome access times out, and neither local nor server has a configured Aliyun CLI. No cloud/DNS/RAM changes, credentials, live delivery, server migration, preview update or installation have occurred.
- Local package: `/tmp/synca-email-desktop-build/Synca Electron-darwin-arm64/Synca Electron.app`. Screenshots: `/tmp/synca-email-ui-evidence/` and `/tmp/synca-email-real-api/`. These are local test evidence, not production acceptance.

### Unresolved regression-suite observation

The backend suite has a full 189-pass result on the final production changes. Additional runs intermittently failed existing AI request tests with unexpected HTTP status or `ECONNRESET`; the failing assertion varied. Diagnostic response assertions and bounded repeats did not establish a root cause (15 consecutive repeats of the original case later passed). Temporary diagnostics were removed; no AI production logic or assertions were weakened. This remains an unresolved validation caveat, not a claimed fix, and must be closed before rollout. Logs remain in `/tmp/synca-email-precommit-test.log`, `/tmp/synca-email-ai-repeat-detail.log`, `/tmp/synca-email-ai-diagnostic-full.log`, and `/tmp/synca-email-ai-final-diagnostic.log`.
