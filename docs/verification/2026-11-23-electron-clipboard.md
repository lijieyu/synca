# Electron copy-button regression

## Cause and change

The record copy button called `navigator.clipboard`, while Electron's permission request/check handlers deny all browser permissions. Electron 45.3.2 reproduces `NotAllowedError`, including for plain text. Native context-menu copies used a separate working main-process clipboard path. The shared error message incorrectly suggested saving an image for a text failure.

Buttons now use a write-only preload/IPC action, sharing the existing native context-menu text/image implementation. The existing platform handler restricts IPC to the owned main frame. Browser permissions remain denied. Image copying retains origin/path, authentication, expiry and current-session checks. The AI settings copy action uses the same text utility. Web continues to use the browser clipboard APIs. Text and image failures have separate localized messages.

## Verification

- Before fix: isolated Electron runtime reproduced browser denial, then failed because `syncaDesktop.copyRecord` was missing.
- After fix: actual system clipboard readback matched synthetic Chinese, emoji, newline and Markdown text. Native PNG write succeeded. External URL, expired image, non-image attachment and signed-out image requests were rejected; offline text copied successfully. Expected rejection logs are emitted by Electron IPC in this test.
- The user explicitly authorized overwriting the clipboard with test text/images. The fixture never reads pre-existing clipboard contents and clears its synthetic content at completion. No production account or data is accessed.
- Shared utility tests passed: desktop text/image dispatch, native failure propagation, Web text and authenticated PNG paths.
- All 12 desktop configuration/release tests passed; three-locale key/interpolation parity passed.
- Web TypeScript/production build and embedded Electron renderer build passed.

Commands: `cd desktop && node_modules/.bin/electron clipboard.integration.cjs`; `cd web && node tests/run-clipboard-tests.mjs`; `node --test desktop/preview-config.test.cjs desktop/mas-preflight.test.cjs desktop/mas/gate.test.cjs desktop/mas/release-config.test.cjs web/tests/locales.test.mjs`; Web `npm run build`; desktop `npm run build:ui`.

## Delivery boundary and acceptance

This is a local source fix and validated renderer build, not an updated installed app or TestFlight delivery. Native preload/main changes require a new Electron package. No production Web/backend deploy or Windows build was performed.

In the next packaged desktop build, verify the record copy button and right-click Copy both paste exact text; image Copy pastes an image; expired attachments remain unavailable; failed copies never show success. Existing Command-C selection copying and browser permission restrictions remain unchanged.
