# Desktop settings restoration — 2026-11-23

## Reconciled baseline

Dot's `origin/dev` ceef58e contains the unified desktop/email changes. The signed Mac TF build85 fixes are on `origin/codex/electron-mas-preflight` 0e84ca9. This task fast-forwarded the existing isolated desktop worktree to that revision. The original `/Users/haer/Projects/synca` checkout and its unrelated edits were preserved.

The installed ordinary Electron already reached the production origin. The new signed TF artifact is deliberately locked to the isolated HTTPS backend. These are separate delivery paths; a successful isolated TF build does not mean the production email backend was deployed.

## Changes

- Fixed desktop settings surface prefers880×620, with viewport clamping and native traffic-light clearance.
- Account overview separates identity, plan, usage and account actions. Plan, login methods and management are actual subpages with an accessible return control.
- First-level sidebar destinations no longer display a misleading back button. Nested account pages retain back; feedback navigation retains the existing unsaved-draft confirmation.
- Shared row spacing, grouped cards, restrained plan styling and AI connection/activity sections. Reduced short-window navigation spacing; feedback footer remains visible.
- Read-only `/auth/capabilities` contract reports email available only after explicit enablement and valid signing/provider configuration. Client treats old-server404, malformed responses and network failures conservatively. The known isolated legacy preview retains404 compatibility; explicit disable/denial still wins.
- Existing browser acceptance scripts updated for the new account hierarchy/capability fixture. They were syntax-checked, not executed via Playwright this turn.

## Verification actually completed

- Web:125 unit tests passed (13files), covering search/pinyin, draft storage, sidebar bounds, categories, attachments, markdown, Apple and email contracts.
- Backend email/auth/binding/configuration:15 tests passed using a local database and mocked external providers. No real emails sent by these tests.
- Electron preview/MAS isolation:9 tests passed. Web, backend, renderer and Mac arm64 builds succeeded. Final app passed `codesign --verify --deep --strict` before and after installation.
- Actual installed production Electron at1040×760: current account and records loaded; account/plan navigation, feedback, general and AI settings inspected. Light/dark checked; original System appearance restored. Cmd+F opened global search, pinyin matched an existing record; Cmd+R retained the existing sync action.
- Actual native window at960×500: account/AI low-height scroll and fixed title inspected. Native pointer resizing did not reach exact640×500; do not claim it did.
- Actual built Web at640×500 in a local synthetic-data frame: account and login-method navigation/return, feedback draft leave/continue preservation and clearing checked. No real feedback sent, account deleted, connection revoked or record modified.
- Independent static review found two issues: compact focus trap start and stale acceptance-script paths. Both were corrected before the final build.

## Delivered

- Local code commit:17bd510.
- Ordinary production Electron installed at `/Applications/Synca Electron.app`; existing profile retained. Native Synca and isolated TF configuration unchanged. This is the local ad-hoc signed arm64 build, not a newly distributed App Store/TF build.
- Formal Web release: `20261123T080605Z-17bd510` at https://synca.haerth.cn/ . Public HTML and all entry-point hashed assets matched the local build byte-for-byte; public health returned healthy. Rollback assets are in the release backup directory.
- Original app backup: `/tmp/Synca Electron-before-20261123.app` (temporary local backup).
- Local real screenshots and comparison: task workspace `work/settings-qa-20261123/`. They include private account UI and were not uploaded.

## Remaining production boundary

The existing production backend/database and mail credentials were not modified. Production email login/binding remains disabled because that backend lacks both routes and configuration; the new UI no longer offers a failing entry. This is not a production email launch. Enabling it requires a separately verified migration against the live schema, safe rollback backend, configured mail sender and real email redemption/identity checks. TF85 remains an isolated test build; no new TestFlight build was uploaded or switched to real data by this task.
