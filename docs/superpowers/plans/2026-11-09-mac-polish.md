# Mac 1.1.0 Polish Implementation Plan

**Goal:** Apply the user's confirmed Mac fixes without redesigning accepted pages or changing Web/iOS behavior.
**Architecture:** Keep existing view hierarchy and API contracts. Share one local pointer reorder stack across the Mac sidebar and manager; share business menu actions across AppKit text and SwiftUI rows.
**Tech Stack:** SwiftUI, AppKit.

## Scope and validation
- All overview: four-square icon, equal 44pt minimum row height, separate spacing, muted unselected versus solid selected in light/dark.
- Category reorder: actual dragged row follows pointer, siblings make room; fixed Default; commit only on release; cancel outside/Escape; restore authoritative order after failure; preserve keyboard accessibility actions.
- Settings: intrinsic content height within available screen, long paths readable, scroll only when needed.
- Context menus: same business actions from body text and row; preserve selection and links; no native editor menu leaking into records.
- Toolbar: selected brush artwork at smaller Mac-only visual size, retain hit area.
- Completed category dot: dim only displayed record dot, not menu choices.
- Verify Mac production build, isolated QA UI with fixture data, drag/save/failure, complete-window screenshots, light/dark and iOS compilation guard.

## Explicitly unresolved
The long-standing Sogou Wubi vertical input jump is not marked fixed. Earlier synthetic IME tests do not establish real Sogou behavior. Installed/running build mismatch and input layout still need separate investigation.

No TF or production deployment requested for this batch yet.

## Final local verification — 2026-11-09
- Production macOS build passed; iOS simulator build passed as a shared-source guard.
- MacMessageMenuTests passed (actions, submenu/checkmark, image data, lifetime, disabled state).
- Isolated local QA app: sidebar reorder persisted without changing selected category; dropping outside the sidebar cancelled; category manager handle reorder and simulated save failure rollback verified.
- Settings checked in Chinese/English and light/dark; no scrollbar at normal content height. Long-text expand/collapse returns to six lines.
- Escape cancellation was code-reviewed; no claim of a GUI mid-drag Escape test. Edge autoscrolling is not part of this implementation.
- Screenshots: /tmp/synca-quality-review/mac-refine-final-main.jpg, mac-refine-settings-zh.jpg, mac-refine-final-menu.jpg.
- Chinese/Sogou composition jumping remains unresolved and is not included among completed fixes. No TF, PR, merge or deployment performed in this batch.
