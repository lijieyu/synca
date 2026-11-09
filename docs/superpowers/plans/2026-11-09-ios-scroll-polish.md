# iOS scrolling and metadata polish Implementation Plan

> Execute inline with systematic debugging and verification-before-completion.

**Goal:** Hide source-device metadata on all clients, expand the iOS new-category palette, and fix image reappearance jumps and long-text collapse positioning.
**Spec:** User-approved conversation on 2026-11-09: preserve action sizes/spacing, preserve data, four equal columns in the new-category form, do not restyle other accepted pages.
**Architecture:** Keep existing SwiftUI/React views. Diagnose lazy row lifecycle and scroll geometry in isolated fixtures before changing scrolling.

- [x] Remove device label and its separator from native and Web metadata; keep model unchanged.
- [x] Add an expanding layout option to CategoryPresetPicker, enabled only in iOS new-category form.
- [x] Reproduce image reload height changes and long-row collapse; add regression coverage, then fix at lifecycle/layout boundary.
- [x] Build iOS and Mac, build Web, run applicable tests, capture native screenshots; report verification limits.

Review focus: late image load, repeated offscreen/on-screen images, collapse at last/penultimate row, category switch during pending scroll, large text and dark appearance.
No deployment or TF requested this turn.

## Verification

- Production source builds: iOS Simulator Production and macOS Release passed.
- Web build passed; Vitest 54/54 and Node tests 3/3 passed.
- iOS isolated UI tests: repeated collapse at the last row and penultimate row,
  full-width palette, and repeated image scrolling all passed. Successful-image
  reset counter remained zero. Device metadata assertions passed.
- Final UI results: `/tmp/synca-scroll-final-v3.xcresult` (collapse/palette passed;
  image test probe referenced the wrong toolbar and was corrected),
  `/tmp/synca-scroll-final-v4.xcresult` (image position/lifecycle test passed).
- Fix requires both resetting stale lazy layout on iOS collapse and targeting the
  ForEach record identity. Scrolling alone still reproduced the failure; that
  attempted variant was not retained. Mac keeps row-local expansion behavior.
- Reviewed actual exported screenshots. Test data is isolated and generated;
  real-device/account acceptance remains outstanding.
- No PR, TestFlight release or deployment performed for this batch.
