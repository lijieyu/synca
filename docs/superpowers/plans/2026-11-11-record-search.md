# Record search implementation plan

**Goal:** Approved search on Web, macOS and iOS without changing composer/feed layout.
**Architecture:** Search the same local synced records as the feed. Raw substring > full pinyin > consecutive initials; creation newest first in tier, stable ID tie break. Includes completed, excludes deleted. Selection closes search, switches to live record category, scrolls original row into view and highlights transiently.
**Spec:** User-approved search Demo and thread 2026-11-11.

## Constraints
- textContent and fileName only; global or current scope; no OCR, typo, arbitrary skip-letter matching.
- Initials minimum 2 letters. Cache transliteration, nonblocking input, cancelled obsolete results, account isolated. No network search/data upload.
- Preserve previous category/scroll on cancel. Never focus composer on result selection.
- Scope-limited small diff. Translated zh-Hans/zh-Hant/en, keyboard, VoiceOver, reduced motion.
- No PR/deploy/TF yet. Test fictional data only. One simulator at a time.

## Review focus
Long and last rows; completed rows; slow image sizing; concurrent remote sync/delete/category changes; manual user scroll must cancel any positioning correction. Avoid automatic bottom-scroll competing with search target.

## Tasks
- [x] Native pure Foundation MessageSearchIndex (new utility), standalone tests first: ranking, pinyin/initials, filenames, deleted/completed, category scope, stable tie, cache invalidation.
- [x] Web index + shared modal UI, header magnifier/Cmd-F, latest result validation; container-scoped scroll/highlight after DOM layout, cancellation and resize guard. Unit and browser tests first, build/lint.
- [x] Native search sheet/header entry/Cmd-F with off-main index; existing reader target, cancel bottom work, transient highlight. Localizations, project registration, both builds.
- [x] Visual QA in isolated fake-data apps, one simulator at a time; cross-platform behavior audit and fresh final review; fix findings and report boundaries.

## Verification and review (2026-11-11)
- Web: 96 Vitest cases, 3 Node tests, production build, focused lint passed. Existing project-wide lint failures remain outside this change.
- Browser fixture: category navigation, last/long/completed rows, delayed images, cancelled search preserving exact offset, stale queries, live move/delete, manual scroll cancellation, mobile/dark/reduced-motion verified.
- Native Foundation search, existing sync/index/cache/media tests, Markdown tests and three-language localization checks passed.
- Mac isolated fixture: Cmd-F, initials, cross-category last-row navigation, delayed image sizing and Escape cancellation exercised in the actual app.
- iOS isolated fixture: completed/last long/image search targets passed, including 8-second delayed image sizing; cancellation preserves original visible record.
- Review fixes: restore temporary scroll suppression on dismissal; retain target until user intent for slow images; align lazy ForEach and explicit row identifiers; preserve production navigation handlers in the fixture generator.
- Final iOS UI regression: last-text collapse and Markdown collapse both passed (2 tests, 0 failures); latest iOS sources compiled in the fixture. Final normal Mac build succeeded. Logs: /tmp/synca-search-collapse-final.log and /tmp/synca-search-mac-final.log.
- Temporary Mac fixture quit and unregistered; no booted simulator remains.
- No production data, PR, deployment or TestFlight changes. Real-device acceptance remains pending.
