# All Overview Implementation Plan

**Goal:** Implement the approved All overview entry in Web; preserve the design decision for later native alignment.
**Architecture:** Keep category selection, focus, sorting and badges intact. Only add a decorative overview icon, selected-state accessibility, and scoped CSS.
**Tech Stack:** React, Lucide, CSS.

## Approved design
- All is a separate overview entry above user categories, with a four-square overview icon.
- Same 44px minimum height and padding as other categories, in both states. Long labels may grow naturally.
- Unselected: subtle black tint in light mode / white tint in dark mode, with a fine inset border.
- Selected: solid black in light mode / white in dark mode, contrasting text and badge.
- Desktop: 16px extra separation before regular categories. Narrow Web: horizontal separation instead.
- Do not use hover as the selected state. Preserve visible keyboard focus.
- Later iOS/macOS: reuse overview hierarchy, equal sizing, clear selected contrast, and spacing adapted to each platform. Do not modify native UI in this task.

## Implementation and verification
- [x] MessageListView.tsx: LayoutGrid icon; aria-pressed selection state.
- [x] calm.css: remove 38px special size; scoped state colors, badges and responsive spacing.
- [x] Build and existing Web tests. Verify light/dark selected/unselected, pointer leave, keyboard and narrow layout in browser.
- [ ] Review, commit/PR and publish Web under the current release authorization. Check production resources.
