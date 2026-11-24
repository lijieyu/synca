# iOS email authentication implementation plan

Goal: complete the approved desktop email flow in native iOS, retaining Apple priority and in-app bidirectional binding. No extra signup or post-login binding prompt. Public Web stays unchanged.

Architecture: existing APIClient contracts and AuthService session completion; a cancellable email flow model and native SwiftUI navigation. Account keeps its two sections with one Login methods destination. System Settings navigation and Mail input/autofill conventions; black/white controls, Dynamic Type and VoiceOver.

Review focus: stale responses after back/logout; retry/expiry/lockout; Apple binding nonce and account collisions; login session and purchase/push lifecycle; long localized content with keyboard.

- [x] Task 1: Add model and API contract tests (challenge, retry delay, expired/locked code, stale completion, binding headers), observe failure, then implement API models/errors and email state machine.
- [x] Task 2: Add login screen email entry, native OTP view, account Login methods and nonce-bound Apple authorization. Reuse approved web copy in three locales; don't expose credentials in errors.
- [x] Task 3: Build isolated fixture, run unit/UI tests, capture light/dark email login and binding, test return/cancel/errors. Shut down reused simulator. Review final diff; report real Apple/email-delivery acceptance separately. No TF/deployment for this batch until requested.

Approved scope: user said “行，补上吧” after the missing native login/binding flow was explained. Continue without another design confirmation.

Verification completed 2026-11-25: 11 unit/contract tests, 3 UI journeys, checked-in Synca Production iOS simulator build and SyncaMac build all passed. Screenshots reviewed in light/dark. Reused iPhone is shut down. Local-only fixture service stopped.

Review resolutions: registered new sources in both checked-in Xcode targets without generator churn; separate send/verify cooldowns; bind Apple using the initiating window and ignore stale controller callbacks; cancel explicit close immediately; announce resend and binding once; fence StoreKit lookups to originating session. The verify-rate-limit and StoreKit session regressions were observed failing then passed after fixes. No deferred findings. Real Apple identity authorization and real mail delivery remain device acceptance, not claimed by the fixtures.
