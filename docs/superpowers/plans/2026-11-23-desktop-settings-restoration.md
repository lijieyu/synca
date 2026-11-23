# Desktop settings restoration and production readiness

> Execute inline with superpowers:executing-plans. Preserve Dot's MAS signing and isolated environment.

**Goal:** Restore the approved Demo's settings hierarchy in shared Web/Electron; produce a production-connected desktop build compatible with the deployed backend.
**Architecture:** Keep existing auth/category/feedback/AI controllers. Reorganize presentation and scoped styling. Detect email capability from backend rather than offering unavailable endpoints. Never reroute an isolated TestFlight artifact or migrate its users into production.
**Spec:** docs/superpowers/specs/2026-11-20-desktop-design.md; reference task work/prototype-2026-11-19/publish/index.html.
**Stack:** React, CSS, Electron, Express.

## Constraints and review focus
- Account first inside settings, bottom-left outside; preserve Cmd+F/R, pinyin search, drafts, sidebar sizing, category ordering and feedback leave guard.
- Preferred settings880x620, clamped for Mac640x500; reachable close/submit; light/dark and English; no horizontal overflow.
- Group identity, usage, benefits, login methods and account management. Nested pages have return; first-level navigation remains consistent.
- Production /me/login-methods currently404. Retain working Apple login/records on old servers; do not show broken binding forms.
- No Windows build, Swift changes, forced logout, preview gate removal, real-user writes or test-account migration.

## Tasks
- [x] Reconcile dev ceef58e, MAS0e84ca9, installed production app, live API and Demo. Existing worktree fast-forwarded; ops notes preserved. MAS/preview baseline9tests passed.
- [x] Restore settings layout and grouped account detail pages: SettingsPanel, ShellPanel, SettingsPanel.css, AIPage.css. Verify rendered UI via CUA, minimum window and draft guard.
- [x] Add read-only email capability contract with conservative old-server fallback: backend app, Web auth capabilities, LoginView/LoginMethods. Test disabled/enabled/unavailable provider and preserve preview.
- [x] Build shared Web and Mac production package. Run focused tests; keep MAS isolation tests green. No claim of TF upload or production email delivery.
- [ ] Record before/after and delivery. Install independent production Electron after acceptance. Backend rollout requires schema/rollback verification first.

## Verification and rulings (2026-11-23)
- Web full unit suite122 passed before three additional capability cases; email client final12 passed. Backend email/binding/configuration15 passed; MAS/preview9 passed. Web, backend and Mac renderer builds succeeded. Final Mac package passed strict deep signature verification.
- Actual installed production Electron: current account/records loaded, grouped account page, plan return, feedback and AI checked; Cmd+F/pinyin and Cmd+R checked. App window1040×760 and960×500 examined. Exact640×500 checked using the actual built Web in a local iframe with synthetic records, including methods return and feedback leave/continue guard. Do not claim exact640×500 native resize verification.
- Fresh review identified compact heading focus trap regression and stale browser-test paths; fixed compact focus and updated mocked capability/navigation expectations. Browser scripts syntax-checked; UI checks used CUA, not these scripts.
- Existing production API remains unchanged; email availability false until compatible configured backend ships. No delivered-code redemption or production email launch claimed.
