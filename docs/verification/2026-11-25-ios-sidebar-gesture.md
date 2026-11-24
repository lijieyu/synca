# iOS sidebar gesture and category icon

## Scope
- Prevent the record feed from scrolling vertically while the left-edge drag opens the phone sidebar.
- Reuse Web/Electron's Lucide Tags vector for the phone sidebar category-management entry, retaining its accessibility label and 44pt hit area.
- Preserve vertical scrolling, partial-drag cancellation, existing sidebar animation and iPad category gesture.

## Implementation
The existing feed viewport bridge installs a directional UIKit pan on the actual UIScrollView. The feed pan waits for that recognizer to fail. Only rightward drags beginning in the left 32pt and exceeding the existing horizontal direction bias are accepted. Other drags are released to normal scrolling. The SwiftUI opener remains for empty/loading phone content and iPad category switching; the populated phone feed uses the UIKit path to avoid simultaneous ownership. The recognizer is removed when its bridge is dismantled.

## Evidence
- Baseline: `/private/tmp/synca-drawer-before-2.xcresult`. A diagonal edge opening moved the same visible record from y=172.833 to y=212.167 (39.334pt). The original closed-drawer assertions also used `.exists`, which was unreliable for accessibility-hidden elements; final assertions use `.isHittable`.
- Fixed: `/private/tmp/synca-drawer-after-3.xcresult`. Both `DrawerGestureTests/testDrawerDragDoesNotScrollFeed` and `PolishTests/testDrawerAndCategoryEditing` passed on the existing iPhone 17 / iOS 27 simulator. Opening and cancellation preserve record position within 2pt; mostly vertical edge movement scrolls; category selection, editing and reordering still work.
- Actual checked-in Xcode project: Production configuration, generic iOS Simulator arm64 build succeeded. Log: `/private/tmp/synca-drawer-production-build.log`.
- Screenshot inspected: `/Users/haer/Documents/Codex/2026-11-25/synca-sidebar/sidebar-light.png`.
- The fixture has isolated example records and loopback-only networking; no production account or data was accessed. The local test server was stopped, and no simulator remained booted after testing.

## Boundary
No TestFlight build or deployment triggered. iOS 16 and physical-device gesture feel were not directly tested; iOS 16-compatible UIKit APIs are used. iPad code path is retained but was not rerun for this phone-only correction.
