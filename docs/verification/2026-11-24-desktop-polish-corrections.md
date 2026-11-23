# Desktop polish corrections — 2026-11-24

User correction takes precedence over the previous visual choices:

- Restore the original green success toast surface (#18752c, white text, 8px/20px padding, 20px radius), keeping its new position centered in the record header. Reserve room for the full pill at minimum desktop width; do not replace it with an icon.
- Restore full-width AI copy instructions button. Keep the already approved tutorial and entitlement states.
- Anchor account popup to a wrapper matching the account button, excluding the settings gear. Match that button's width and keep the 8px vertical gap.
- Remove the feedback outer scrollbar gutter and footer gutter. Compensate the form's actual native scrollbar width only, so both classic and overlay scrollbars preserve equal panel insets and alignment with the fixed footer.

Validation: 20 desktop browser regression checks passed with isolated fixture accounts; assertions cover green toast, full-width copy action, popup/button width equality, equal feedback insets, scrolling, minimum width, shortcuts, pinyin search, category ordering and existing mobile paths. Web build and Electron shared renderer build passed. Screenshots saved in /private/tmp/synca-corrections-evidence/after/.

Delivery scope: preview frontend only. No production Web, backend, database or TF update.

Workspace recovery: original Documents worktree became cloud placeholders and reads stalled. Continued from the exact local commit 389c1ab in /private/tmp/synca-desktop-corrections-20261124. Original worktree and unrelated pending email documentation remain untouched.
