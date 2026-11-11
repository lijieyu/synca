# Search regression round 3 — eight user findings

Scope: fix user's seven screenshots/eight findings in place; no release authorization in this turn. Preserve original font weight, layouts, relevance sorting and editing behavior. Actual screenshots required, no claim that untested hover is passed.

## Root causes and acceptance
1. Web hover: asymmetric pseudo-element top0/bottom6. Equal inset, no divider contact. Native locate: divider sits at row bottom but next row has12pt gap; center separators in the existing gap without shifting content, background stays symmetric around content. Web locate needs horizontal breathing room without layout shift.
2. Search input flex: width100% input competes with shrinking magnifier when clear exists; fix icon and field flex contract. Verify empty/typing/marked text widths equal.
3. Native locate card same as1; actual light screenshots.
4. Mac per-row AppKit hover feedback/lifecycle: reproduce and replace stale/reentrant updates; prove entry and exit, only one hovered row, empty area clears all. Review opening responsiveness.
5. Excerpt: inconsistent12/24 pre-hit characters, no tail backfill; Web slices before whitespace normalization. Unify compaction/window mapping, 3-line display, desktop/mobile context budget retaining visible match.
6. Web focus: Escape restoration changes focus-visible modality; pointer-return must not paint thick outline. Neutral lightweight keyboard focus retained. Cover delete/edit/brush + editor autofocus, both themes.
7. iOS brush same silhouette, stroke1.7→1.4, hit area unchanged.
8. Native locate scroll: second positioning pass always targets interior hit at .top, clipping even cards that fit. Measure selected row/viewport; center whole cards that fit, only deep-hit anchor for oversized cards. Preserve late-image corrections and user-scroll cancellation.

## Targeted evidence
- Web isolated browser red baseline identified 7 failures; all corrected assertions pass. Production build, existing search browser suite and new polish suite passed. Both-theme screenshots saved; desktop/mobile tail previews retain visible match across three lines. Changed-file lint passed; full lint has pre-existing failures outside scope.
- Native full-card visibility test failed before fix (top 216.33 vs minimum224.33), passed after fix. Three iPhone UI tests passed: full-card visibility, typing/glyph stability, folded-tail navigation. Fixtures contain only fabricated records. Post-location collapse now cancels pending search positioning to prevent later callbacks from pulling the viewport again.
- Tests to run only affected suites; no blanket rerun at later TF if exact verified revision unchanged.

Evidence directory: `/Users/haer/.codex/visualizations/2026/11/05/01a1ac56-c8f9-73c1-b1d6-a3f7776c2997/search-round3-20261111`. iPhone locate highlight is an unmodified frame from simulator recording, not a recreated screenshot. No simulator left running. Mac actual component verification passed in an isolated NSWindow host using current production MessageListView/MessageSearchView and the same environment objects. Real pointer swept three rows, only current row highlighted, blank-area exit cleared all; light/dark screenshots saved. Tail keyword preview and long-text navigation verified. Production WindowGroup startup and MacBook perceived opening latency remain unverified. The normal macOS UI test runner was killed before test connection; no passing XCTest claim is made. Earlier same-ID round2 screenshots were discarded.

Final Mac evidence: `synca-r3-component-light-first.png`, `synca-r3-component-light-exit.png`, `synca-r3-component-light-tail.png`, and `mac-locate-highlight.png` in the evidence directory. Whole-card example is the first record: full bounds visible, scroll constrained by top edge; no claim of strict viewport centering. All QA hosts and simulator sessions stopped. No commit, PR, TF or deployment performed in this batch.

## Follow-up: iPhone top breathing room
The previous screenshot is the first completed record in its category. iOS row top padding is 8pt, while the highlight's 6pt vertical inset consumed all but 2pt. Keep the highlight's top at the row boundary on iOS, retain bottom inset and unchanged geometry. Middle rows retain the previous separator outside the background, with 6pt clearance. Reuse the existing UI fixture/build and run only first/middle full-card visibility, capturing the transient real highlight.

Follow-up verified: first/middle full-card visibility test passed; unmodified recording frames saved as `iphone-top-spacing-first.png` and `iphone-top-spacing-middle.png`. Both inspected: added top breathing room and previous separator outside middle highlight.
