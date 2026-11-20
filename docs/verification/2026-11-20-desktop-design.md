# Desktop design verification — 2026-11-20

## Scope and source

- Branch: `codex/desktop-design-20261120`; baseline `e169bd7` snapshots the actual current Web/Electron working source before this change. Earlier historical changes in that snapshot are not this redesign.
- Original `/Users/haer/Projects/synca` working files were not edited. No backend, iOS or native macOS code changes in this task. No Windows build or production deployment.
- Shared desktop styles and minimal navigation changes retain existing stateful components. SidebarFrame, InputBar, composerDrafts, MessageBubble and search-worker source are unchanged from baseline.
- Desktop search is global; mobile search keeps its original range selector. Cmd/Ctrl+R and native menu emit manual sync; APNs/wake/show refresh remains silent and retains write guards.

## Validation

- `web/tests/desktop-design.browser.mjs`: 11 groups passed on the final CSS/source. Checks sidebar default/min/max (236/200/360), mouse/keyboard/persistence/narrow-then-grow; global Chinese/full-pinyin/initial search and late long-text navigation; sync without navigation/draft/selection/scroll loss; desktop/minimum light/dark presentation and settings guards; per-category drafts, synthetic IME, task patch and editor preservation; category keyboard/pointer reorder and persistence; 320/390px mobile preservation; responsive search scope; all settings child pages at 640×500 with English and keyboard focus.
- Existing `run-search-tests.mjs`: 14 passed. Existing draft/preferences/download/category-edit/locales Node tests: 6 passed. `run-desktop-preservation.mjs` executes existing sidebar-width/category-sort/Markdown tests: 14 passed.
- Web TypeScript + Vite + AI page build passed (`VITE_PREVIEW_PRICING=true`); Electron renderer TypeScript + Vite build passed.
- `desktop/verify.mjs`: passed on actual packaged .app with temporary profile/database and local service. Covers native menu edit/delete cancel, sync menu without reload, silent background refresh without toast, draft reload, download location/file, native settings, minimum window, synthetic IME, search focus and jump, second-client edits, hidden-window sync and Dock badge, shared settings/Markdown check-edit-persist, offline cache. Final follow-up only changed selected-category count color; rebuilt both bundles, reran browser suite and verified installed package/signature.
- Independent review found mobile scope/feedback spillover, automatic sync toast and secondary contrast. Fixed and reran affected checks. Unselected secondary text #6d6674 reaches 4.97:1 on sidebar; selected counts use primary text to remain readable with arbitrary category colors.
- Visual inspection: 1280×800 and 640×500 homes, light/dark settings, feedback/categories/AI/about, English narrow native desktop settings. Browser captures use fictional records; native captures use local fixture account.
- `git diff --check` passed.

## Delivered artifacts

- Installed and running: `/Applications/Synca Electron.app`, version 1.2.0. `codesign --verify --deep --strict` passes, installed ASAR matches tested source package.
- Final ASAR SHA-256: `67b69dbdea7b04efd58b11c5ea435066cb976e4150c27ba2b338ca052d34ecca`.
- Existing Electron 45.3.2 runtime reused byte-for-byte because the cached runtime/dependencies had cloud-evicted files; locked build dependencies restored separately. Framework SHA-256: `6f6bc9af3f5865dfba7244b30022a711b2b091cff8b0817e8b79fdfc19574f1d`. Proper ASAR packaging and ad-hoc signing retained.
- Original app rollback: `/private/tmp/synca-desktop-design-build/previous-installed.app`. No user profile reset.
- Web: https://synca-preview.haerth.cn/ → `/opt/synca-preview/web-releases/20261120-desktop-design-132353`. Only static files changed; previous hashed assets and independent demo routes preserved. Existing backend PID 2834108 remained running.
- Verified actual HTTPS response against staged index and JavaScript. Index SHA-256: `9bd67f45098f06b80ab554a8315849f2cbbb6685fb91cc7e2f2843c3f37b1e2e`; script `index-vtYgylzA.js` SHA-256: `9f9877ebbc148419890012c6928e66f8c84177554dd1567f5cd3917528df8349`.
- Preview health returned ok. Original pre-task static rollback: `/opt/synca-preview/releases/20261109T073509Z-7e0e6d0-preview/web-before-desktop-132157`.
- Production `/opt/synca/web/index.html` SHA-256 remained `3d2b13b1ce89c4dcfefeca63bc6ed8ac4591ef25a8bcd1ff5630014a3fbe194a`.
- Local comparison report: `outputs/desktop-release-20261120/前后对比与验收.md` under the task directory; images from baseline and real changed product, same fixture content.

## Limits

Synthetic IME events do not establish a fresh long-duration real Chinese input-method benchmark. Tests cover named flows, not every account/purchase/network/device state. APNs receive plumbing was retained; no live APNs delivery test performed. Windows and iOS are out of scope. Production services and data were not migrated.
