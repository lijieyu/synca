# Windows compatibility test packages — 2026-11-24

Base: `9883fcbc4e7c7c9c629ef177de49a365a6fa92c4` (released fixed shortcut reference). Branch: `codex/windows-compat-20261124`.

## Changes

- Add Windows ARM64 packaging beside x64; shared bundled renderer and production service. Desktop retains email login. No Web deployment or Mac TF trigger.
- Preserve at least 640×500 content DIP by including native Windows frame dimensions in the outer minimum. Keep existing Windows system title bar and Mac hidden-inset layout.
- Add Windows Ctrl+Shift+Delete to clear completed records through the existing scoped confirmation. Match help, tooltip, native File menu and renderer; protect IME, repeat, drafts and other dialogs. Browser Ctrl+Shift+Delete remains untouched.
- Sanitize attachment/download filenames for Windows forbidden characters, DOS device basenames, trailing dots/spaces and UTF-16 length, retaining ordinary Chinese and extensions.

## Completed verification

- Electron official 45.3.2 ARM64 and x64 runtime ZIP checksums match the installed Electron checksum manifest.
- `node --test *.test.cjs mas/*.test.cjs`: 16/16 passed, including new Windows filename, frame-size and shortcut checks. Regression tests failed on the original implementation before fixes.
- Isolated browser shortcut suite: 6/6 passed, covering Web/Mac/Windows help, 640×500, light/dark, English, scoped confirmation, drafts, IME/repeat and browser shortcut exclusion.
- Shared desktop renderer TypeScript and production build passed.
- Real Mac Electron isolated smoke passed: native key/menu confirmation, scoped deletion, menu availability, normal/minimum layouts and zoomed accessibility.
- Both Windows packages built on the Mini. Executable PE machines verified as ARM64 `0xaa64` and x64 `0x8664`; packaged source and renderer assets match build input; runtime locales/resources are present; no preview marker or development secret files in app.asar.
- Identical app.asar SHA256 in both packages: `28724f442d71e13982f024dbc0ea72a2d29574d6c9736b5c5015b9a42a683e7e`.
- Independent source review: no blocking findings.

## Pending Windows VM acceptance

This is a cross-build plus simulated-platform verification, not proof of Windows runtime compatibility. No Windows VM was available during packaging.

1. Unzip the whole folder; launch on matching Windows architecture. On Apple Silicon Windows ARM, use ARM64 first. x64 emulation on ARM does not substitute for native Intel/AMD verification.
2. Apple login and email login, relaunch/session restore; app-internal bidirectional binding with designated test accounts.
3. Microsoft Pinyin continuous composition, Enter confirmation, editing, text/image copy and paste; image/attachment save to a Chinese directory, including sanitized filenames.
4. Ctrl+F pinyin/global search and scroll targeting; Ctrl+R sync without page reload or draft loss; Ctrl+, settings; Ctrl+Shift+Delete scope/confirmation/cancel.
5. Resize to minimum, maximize/restore, display scale 100/125/150%; light/dark and English settings, popovers and long labels.
6. Close/Ctrl+W hides to tray; restore preserves UI. Change records on phone while hidden and check tray count after background refresh (30 seconds when network is available); tray Quit exits; second launch restores one instance.

These packages connect to the existing production service and real account data. Create dedicated test records for delete/clear verification.
