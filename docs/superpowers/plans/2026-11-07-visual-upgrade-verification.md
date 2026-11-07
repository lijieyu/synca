# Synca visual upgrade — verification record

Scope: iOS, macOS and Web product presentation and device-local preferences. Backend contracts unchanged. Native and Web changes are prepared as separate review PRs. No TestFlight distribution is claimed.

## Implemented
- One stream; desktop category sidebar with Add Category after the categories. iPhone retains horizontal categories and exposed add/clear-completed controls.
- Desktop account and plan at bottom left, free daily usage exposed, one management menu. Feedback/About/Sign out share the final group.
- Settings language: system, Simplified Chinese, Traditional Chinese, English; appearance: system/light/dark. Mac folder selection and optional per-download prompt. Web folder writing when supported, browser fallback otherwise; folder choice is explicitly page-session scoped.
- Native Foundation/AppKit strings and SwiftUI presentations use the chosen locale; sheet/popover boundaries observe preferences without resetting view identity.
- Existing authentication, text editing restrictions, attachment lifecycle, categories, account, purchases, AI connection and feedback paths retained.

## Verification
- iOS Production simulator and macOS Production builds succeeded; Web TypeScript/Vite production build succeeded.
- Localization parity: native 300 application strings and 3 privacy strings; Web 302 keys. Three languages checked for missing keys and placeholder parity.
- Native regression: pure-text edit boundary; timestamp parsing; authenticated attachment origins; safe filenames; duplicate file preservation; mutation/session fences; ordered writes/logout removal; 10,000-record ordering/index; CJK editor wrapping, symmetric insets, trailing caret, overflow and IME/selection preservation.
- Transfer suite: 200 MB streamed multipart, retry identifier preservation, cancellation, attachment cache budget/TTL/eviction, HTTP 410, redirect/origin checks and image downsampling.
- Web behavioral checks: same-name concurrent downloads preserve both contents, permission failure fallback, preference routing, 1280/390/320 layouts, light/dark, locale changes preserve composer and editor drafts, zh-Hant AI guide URL.
- Independent native and Web reviews: fixed download reentry, missing category colors, default-send-category notification, directory-write race, and account quota VoiceOver value.
- Native actual-view QA uses an isolated bundle and fixture records, no production credentials. Mac screenshots and AX inspection verified exposed add/usage, menu→settings navigation, Traditional menu/sheet strings, immediate language changes, purple Done action, dark appearance and composer draft preservation.
- iPhone fixture installed/launched in QA simulator; interactive simulator surface unavailable to the UI tool, so no iPhone visual acceptance claim. Physical-device, StoreKit purchase and production release acceptance remain for TestFlight.

## Artifacts
- `/tmp/synca-mac-dark.png`
- `/tmp/synca-mac-settings-dark.png`
- `/tmp/synca-web-desktop.png`
- `/tmp/synca-web-mobile-dark.png`
- `/tmp/synca-web-320.png`
- `/tmp/synca-web-settings-dark.png`

## Release boundary
The isolated Web preview was provisioned separately (see scripts/preview/README.md). The subsequent PR-only handoff does not deploy Web, merge either PR, or distribute native builds to TestFlight. Existing unrelated build-output/user-data changes preserved. Full-repository Web lint has inherited errors in AdminLayout, AuthImage, LoginView and AuthContext; changed-file diagnostics match HEAD: seven existing `any` errors in client.ts and two existing effect warnings in MessageListView.tsx. No new lint diagnostics remain.
