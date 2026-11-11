# Search acceptance round 2 — approved implementation

Status: user approved divider-with-clearance demo and explicitly corrected keyword emphasis: preserve original font/size/weight; background only. Implement locally, verify real built apps and capture screenshots.

## Complete scope
1. Force 24-hour time in main records and search on all platforms, independent of system 12-hour preference. Keep accepted date rules.
2. Remove per-keystroke spinner/loading label on Mac, Web and iOS. Keep previous completed results while computing; do not flash empty state or count during intermediate work. Do not block the main thread. Preserve actual error feedback.
3. Unify keyword highlight geometry: complete glyph coverage, no underline or clipping; support Chinese/Latin/descenders and wrapping, light/dark and Dynamic Type. Demo proposes a tiny-radius blue marker, original font weight, no layout-size change.
4. Keep existing cleaning brush silhouette. Balance visual stroke weight with search/refresh on Mac/Web; enlarge iOS painted size without changing hit target or toolbar spacing. Enabled/disabled colors unchanged.
5. Make located original-record background clearer in light mode, with a restrained fade, no outline or geometry changes. Distinguish from keyword marker and hover.
6. Web search field must keep the same height with empty/nonempty/clear-button/composition states. Investigate computed sizes before fixing.
7. Mac hover must work on first pointer entry without clicking. Separate rounded background from divider (no tails), including original-record locate highlight and iOS pressed states. Demo compares inset separators versus no separators.
8. Web/iOS IME: keep results and count for last committed query during marked text; only run the new search after composition commits. Test cancel, replacement selection, clear, rapid typing, stale response and scope changes. Check Mac for regression.

9. Web edit record: on opening focus the text end and reveal caret; do not reset selection on later renders or disrupt IME.

## Source findings, not yet runtime-confirmed fixes
- Native `searching` replaces results with ProgressView on every changed query.
- Web `busy` hides results and renders search.loading; input onChange has no composition guard.
- iOS editingChanged forwards marked text immediately; updateUIView also calls unmarkText when binding differs. Requires coordinated draft/committed-query handling, not just removing spinner.
- Native hover state is held in ButtonStyle; first-hover behavior requires actual built-app reproduction.
- Web clear control is conditional and has a 28px height; check flex/box-model and inherited styles for field growth.

## Verification gate after approval
- Empty/nonempty and IME transitions never flash loading or clear prior committed results.
- Record field heights before/after typing, clearing and composing.
- First hover on a newly opened Mac search window; keyboard focus remains accessible.
- Chinese/Latin, ascenders/descenders, multiline marks; light/dark and enlarged text screenshots.
- All three toolbar icons at actual size, enabled and disabled, mobile and desktop.
- Search ranking, counts, timestamps and locate/scroll behavior unchanged except listed fixes.

## Implementation sequence
- [x] Web: add browser regression for stable field height, IME candidate retention and no loading; implement draft/committed query separation and retained results in MessageSearch.tsx; CSS isolated fixed field geometry, normal-weight marks, divider clearance; enforce 24h in messageTime.ts. Run search tests, browser tests and production build.
- [ ] Native: composition-aware UITextField/NSTextField committed query; retain results instead of replacing with spinner. Move hover state into a stable View, separate divider. Render full-glyph background without weight change. Enforce 24h in SyncaMessage. Verify unit tests, iPhone/iPad UI and actual Mac first-hover.
- [x] Toolbar/locate: preserve brush outline, thin desktop stroke, enlarge iOS optical size; increase locate blue and inset it from separator without changing layout.
- [ ] Final: inspect light/dark screenshots with Chinese/Latin/multiline, real IME transitions and clear action; no release or claimed completion without evidence.

## Verified evidence (2026-11-11, local only)
- Web production build, edited-file lint and 12 search/time unit tests passed. Full isolated browser regression passed: fixed 52px field, marked-query retention, Escape composition cancellation, clear, normal Escape, short/long editor initial end caret and preserved later selection. `/tmp/synca-search-round2-browser.log`.
- Real UIKit input tests passed for commit without editingChanged, candidate cancellation, external clear, fresh empty-query candidate clear. `/tmp/synca-round2-input-final.xcresult` (3 tests). These use real UITextField marked-text APIs, not a physical third-party input method.
- iPhone UI regression passed: query/glyph rendering, no spinner, folded tail reveal and stable scroll, dark results. `/tmp/synca-round2-phone-final.xcresult` (UI cases passed; its earlier input-clear failure is superseded by the successful final input suite).
- iPad UI query/glyph regression passed; `/tmp/synca-round2-ipad-verified.xcresult`. One simulator at a time; closed after tests.
- Actual isolated Mac app inspected for normal-weight Chinese/Latin highlight, count/layout and 24h dates. CUA scroll pointer relocation did not establish true mouseEntered/mouseMoved; first physical hover remains a manual verification item, not claimed passed. Explicit row tracking geometry and delayed-first-selection guard added.
- Screenshot directory: `/Users/haer/.codex/visualizations/2026/11/05/01a1ac56-c8f9-73c1-b1d6-a3f7776c2997/search-round2-20261111/`.
- Old OS fallback (iOS 16–17 / macOS 13–14) uses full-glyph AttributedString background; tiny rounded marker requires iOS18/macOS15 TextRenderer. Neither fallback nor modern path adds font weight.
- Review also found fresh IME clear affordance and Web Escape cancellation gaps; both corrected with regression coverage. No PR, release or production deployment for this batch yet.

- Final Mac compile passed: `/tmp/synca-round2-mac-final2.log`. Reopened built app and entered `ms`; field retained `ms` and showed 3 results. Hover remains explicitly unverified with actual pointer movement.

## Release verification
User authorized TF (iOS/Mac normal PR packaging and Web production) after reviewing the acceptance list, including the explicit physical-hover verification boundary.
- Rebuilt Web production output; reran the 12 search/time tests, native search regression, and full isolated browser flow successfully.
- Final native build and UIKit/iPad evidence above reviewed; no additional native edits since the final Mac build.
- Release scope is this search refinement batch and Web edit-caret fix only. No backend/data migration.
