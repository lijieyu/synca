# Fixed desktop keyboard shortcuts — local review

## Approved scope

- General settings shows a read-only shortcut reference directly below appearance/language. Explicit fixed/non-editable copy, no extra navigation item or customization.
- Web lists search/sync with the host modifier. Mac Electron additionally lists clear completed (Command+Shift+Backspace), settings, close and hide.
- Browser clear-data shortcut is deliberately not intercepted by Web.
- Mac keyboard, File menu and unchanged broom icon use the existing scoped confirmation and deletion endpoint. Preserve drafts; guard composition, repeat and other dialogs. Disable clearing when the current scope has no completed records.
- Initial delivery was local implementation and screenshots only. The user subsequently confirmed this exact result and authorized production Web deployment and the normal Mac TF merge/build flow. Production Web must keep email login hidden; Mac retains it. No backend, installed-app replacement, or live-record mutation is required.

## Verification

- Web production build and Electron shared renderer build passed.
- Full isolated browser regression: 24/24 passed. After the final narrow-layout fix, reran the 8 affected shortcut/mobile/settings checks: 8/8 passed. Existing pinyin/search/time helpers: 14/14 passed. Three-locale key/interpolation parity passed.
- Electron 45.3.2 executed the actual app/main/preload and built renderer in an independent offline fixture profile. Main-window key delivery and native menu both open the confirmation; confirming a category sends that category ID, removes its completed item, and disables the menu. No live API used.
- Real Electron layouts: 1040×760 light/dark and 640×500 Chinese/English. At minimum size, body clientHeight and scrollHeight are both 350px; no vertical or horizontal overflow. At 125% zoom, the final shortcut remains reachable by scrolling.
- Visually inspected native light/dark/minimum and Web normal/minimum screenshots. Browser capture waits for repaint after resizing.

## Review fixes

1. Mac does not support `registerAccelerator:false`. Added a `before-input-event` guard before Chromium/native-menu handling, suppressing composition/repeat and emitting only one command. The added native guard assertion failed before the fix and passed afterward. Explicit menu selection still uses the same renderer guard.
2. General help must remain available when zoom crosses the compact-layout breakpoint. Replaced width-based omission with General-section membership. The zoom assertion failed when help disappeared, then passed after the fix.

Windows runtime and iOS are outside this change; no Windows package was built. Network propagation was not tested against real user data; the existing clear API and refresh flow are unchanged.

Evidence: `/Users/haer/Documents/Codex/2026-11-24/synca-shortcuts-review/` (screenshots, browser/affected results, Electron checks, build logs).
