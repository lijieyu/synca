# iOS settings refinement — approved scope and plan

## Design

Information display, navigation and input polish. Existing-experience corrections; no new feature or repeated KANO assessment. User approved a logo + Synca drawer header, avatar/account + gear as one settings target, and three account groups (identity; plan + storage; sign out + delete). Keep destructive confirmation and red delete text. Use Settings-style grouped information and native text sizing, with the existing shared AI flow and monochrome actions. Alternatives rejected: another chevron, redundant account action menus, or five separate cards.

AI guide: adapt only the iOS host to the native system background and 17pt body / approximately 15pt secondary text, scaled with Dynamic Type. Preserve tutorial order, full-width copy button, connection actions and origin restrictions. Feedback fields: neutral adaptive grayscale fill, no purple cast. No automatic TF or Web deployment.

## Implementation and validation

1. MessageListView: reuse LoginLogo at 32pt; retain the 44pt account hit target and explicit settings accessibility label.
2. AccountSheet: keep Form and combine sections without changing actions or navigation.
3. AIConnectionView: host-scoped presentation styles, native/WebView background alignment, runtime appearance and Dynamic Type updates; no desktop style change.
4. FeedbackComposerView: neutral adaptive fill and text; preserve draft protection, photo selection and validation.
5. Reuse the existing iPhone simulator alone. Capture drawer/account/feedback in light/dark and AI free/Pro/connected states; exercise plan back, draft cancel and AI instruction expansion plus large type. Shut down after captures. Verify metadata and affected compilation. Present local screenshots before release.

## Verified locally

- Final iPhone 17 / iOS 27 simulator run: `testAIPlans` and `testSettingsRefinement` passed, 2 tests / 0 failures (`/private/tmp/synca-settings-refinement-final.xcresult`). AI covers free light/dark, Pro light/dark, connected dark and accessibility XXXL; instruction expansion and scroll-to-action verified.
- Visual review caught ambient tint in the feedback sheet. Set explicit native background for its content and navigation bar; targeted final rerun passed, 1 test / 0 failures (`/private/tmp/synca-settings-neutral-feedback.xcresult`). Drawer → Settings → Account → Plan → Back and feedback draft cancel/preservation verified in both appearances.
- Neutral feedback captures visually rechecked. Account captures include storage; three grouped sections are visible. Delete handler and confirmation were preserved, not executed against any account.
- Screenshots/gallery: `/Users/haer/Documents/Codex/2026-11-24/synca-ios-settings-refinement/index.html`.
- Validation uses an isolated app identity, example account and loopback HTTP fixtures. It does not claim new real-account OAuth, payment, APNs or sync validation. Real network/auth behavior is unchanged.
- Release metadata check (1.2.0), Python fixture syntax and `git diff --check` passed. Test simulator is shut down and loopback server stopped. No push, TF, Web deployment or version bump.


## Follow-up decisions (2026-11-24)

- The user clarified that account identity is display-only. Use two account sections: identity + current plan + storage; sign out + delete. Retain the existing account actions and confirmations.
- Restore compact AI typography (15pt body / 13pt secondary, Dynamic Type scaled) while retaining corrected native light/dark backgrounds. Put revoke alongside the client name, not at the bottom right. Reuse 18 local EverBond client icons with display-only alias matching; unknown clients use a link symbol. Shared Web/Electron AI page gets the same icons and connected-row structure.
- User withdrew the two-key shortcut request. Shortcut implementation, menu/help and associated test edits from this turn were reverted. Retain Command+Shift+Backspace on Mac and Control+Shift+Delete on Windows.
- New screenshot shows UIKit's default URL preview loading an empty remote page on long press. For iOS 17+ customize the text-item menu configuration with no preview while preserving all system menu actions and default tap opening. iOS 16 keeps its existing system behavior; no private APIs or broad text-view rewrite.
- Verify local browser, real Electron and reused iPhone simulator behavior; present screenshots. No release/deployment in this task.

## Round 3 verification and desktop record corrections

- Latest desktop findings: pointer focus kept record actions visible through `:focus-within`; unexpired attachment expiry appeared before the image; image hover applied a vertical transform. Actions now reveal on hover or keyboard-visible focus, expiry lives in the footer metadata row, and image hover does not move the image. Shared Web/Electron changes only.
- Three targeted browser regression checks passed after reproducing all three failures before the fix: copy then pointer exit, keyboard focus retention, expiry footer alignment and narrow layout, image hover geometry. Light/dark screenshots visually reviewed.
- AI brand and Windows compatibility tests: 6 passed. Web TypeScript build and Electron renderer build passed. Shortcut source and related tests have no diff; the withdrawn two-key change is not included.
- Native account/AI/feedback tests passed in the isolated fixture (`/private/tmp/synca-round3.xcresult`). Earlier long-press test was a false positive because generic record Copy was accepted; it is not counted as successful URL verification.
- Precise URL long press visually shows the native Open Link / Copy Link / Share menu without remote preview (`link-long-press.png` in the gallery). Short tap opens Safari (passed in `/private/tmp/synca-round3-links-singleline.xcresult`). URL menu automation still fails after waiting for application idle; Copy Link execution is not yet verified. The test now rejects generic record Copy explicitly. This is an outstanding validation item, not an all-tests-passed claim.
- Current screenshots: `/Users/haer/Documents/Codex/2026-11-24/synca-settings-round3/index.html`. Local only; no submission, deployment or packaging for distribution.

## Round 4 — drawer quota, alignment and native upgrade

- Move the existing daily quota below the drawer account/settings button; preserve its free-plan visibility rule.
- AI connection headers now place icon, name and revoke in one vertically centered grid row; dates occupy the following metadata row. Shared Web/Electron/iOS content uses the same structure.
- Rename the free-plan action to “升级 Synca Pro” (localized), use one full-width primary button and a secondary refresh action below. The authenticated native guide opens the existing AccessCenterView through a main-frame, first-party-origin/path-validated handler. Closing refreshes Web entitlement status. Regular Web retains its existing plan/App Store path.
- Verified 4 browser checks: 390/1100 alignment and all client assets; free-plan Web and native routing. Six unit/compatibility checks passed; Web TypeScript/Vite and Electron renderer builds passed.
- iPhone simulator test `testAIUpgradeAndDrawerPlacement` passed in light/dark (91.5s, 0 failures): quota below account, native Synca Pro sheet and restore action present, close returns to AI, connected state captures. `/private/tmp/synca-round4.xcresult`.
- Native sheet uses the existing StoreKit flow. The isolated test bundle cannot load production App Store products, so this verifies navigation/return, not product loading or a purchase transaction. No real purchase or restore was performed.
- Final screenshots visually reviewed: `/Users/haer/Documents/Codex/2026-11-24/synca-settings-round4/index.html`. Simulator shut down; fixture server stopped. No commit, deployment or TF submission. Previous URL-menu automation limitation remains unchanged.
