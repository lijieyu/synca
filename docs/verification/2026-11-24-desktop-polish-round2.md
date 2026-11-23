# Desktop UI polish, round 2 — 2026-11-24

Scope: shared Web/Electron frontend; deploy preview only. Production Web, API, databases and TF packaging are not part of this change.

## Decisions and changes

- Sync success is centered horizontally and vertically in the record area's header, excluding sidebar width. It lasts 2.2 seconds, does not move controls, and has a polite status announcement. A permanently reserved center slot prevents long titles from colliding; compact headers may show only the check. Existing mobile toast behavior stays intact. Cmd+R still synchronizes without navigation.
- Account menu matches sidebar content/category button width and follows sidebar resizing. Its bottom is 8px above the account row, independently of the free account quota. Identity stays non-interactive; approved menu items and separators are unchanged.
- Feedback action stays 24px above the panel bottom, aligned with inputs. The form scrolls separately; both form and action area reserve the same scrollbar gutter. No action divider.
- Appearance/language use custom Web listboxes with checkmarks, viewport-aware positioning, keyboard selection, Escape/focus return, outside-click dismissal and Tab focus containment. Preferences remain persisted through existing handlers.
- AI tutorial renders independently of the connection-list request. Free accounts see guide and upgrade; Pro without connections sees guide and copy instructions. Existing connections/history and consent flow are retained. Preview restrictions have a friendly notice and do not expose internal errors or enable unavailable copy actions. Reload errors support retry; upgrade refresh is a secondary action.

## Validation

`web/tests/desktop-design.browser.mjs`: all 20 checks passed using an isolated in-memory API. Coverage includes pinyin/global search and scroll positioning; Cmd+R draft/selection preservation; sidebar resizing; category sorting/IME/Markdown task interactions; existing mobile paths; settings bounds; free/Pro/restricted/failed/connected AI states and retry/back; selector keyboard/focus/persistence; fixed feedback action alignment; menu anchoring; centered sync feedback with long titles.

A separate read-only review reproduced two edge cases (Tab escaping the dialog, sync icon over long titles). Both were fixed and added to regression assertions before the final passing run.

Three-locale key/interpolation parity passed. Shared Electron renderer build passed; this is frontend build verification, not a new signed Mac or TF package.

## Screenshots

Actual rendered UI with isolated example accounts, not production account changes. Both free and Pro screenshots use fixture entitlements; they do not claim preview AI connectivity. Preview continues blocking AI operations.

Artifacts: `artifacts/2026-11-24-polish-round2/` under the parent task workspace. Includes AI free/Pro/preview-restricted, feedback, appearance/language menus, account menu, content-centered sync and a window-centered comparison only, plus minimum-window/light variants. Only content-centered sync is implemented.
