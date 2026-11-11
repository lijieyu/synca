# Search walkthrough fixes — final scope and evidence

Approved 2026-11-11. This supersedes tentative layout proposals in search-polish.md.

## Final acceptance contract
1. Native empty query shows prompt immediately, never loading. Background refresh must not flash/reset results.
2. Web zero-result state centered in remaining content area.
3. Three-language empty prompt complements placeholder: 输入关键词，查找你的记录.
4. Web straight separators independent of row rounding, no separator after last result.
5. Web sidebar complete keyboard focus ring, including first/last category and resized sidebar.
6. Mac/Web restore All overview icon and proper inset; iOS/iPad no icon.
7. Web neutral clear control; accessible label and keyboard operation.
8. All platforms cleaner restrained blue keyword emphasis.
9. Search metadata: category + completed-only status on left, timestamp on right. No pending label.
10. Main list and search share time rules: today time; yesterday + time; same year month/day + time; older year date + time. Localized, system time convention.
11. Located search target: background-only emphasis, no outline; stable scrolling, no geometry change.
12. Mac top buttons equal hit areas/center spacing, no search button background.
13. Short excerpts keep beginning; long excerpt shows matched content. Selecting a hidden long-text match must reveal it, not leave it collapsed.
14. Native result counts aligned with Web and actual result count; no count for empty query or zero-result state.
15. Web/Mac results scrollbar must not cover row information, without permanent wide gutter or clipped rows.
16. Preserve existing literal > pinyin > initials ranking, newest-first within rank; retain query behavior and unrelated accepted layouts.

## Implementation and verification
- Independent Web and shared native changes, coordinated using this exact contract.
- Unit coverage for ranking, excerpt and timestamp boundaries; browser background polling/focus/scroll/empty-state tests.
- Native isolated fake-data app, one simulator at a time. Test long/image/completed navigation and capture light/dark result, empty state and toolbar.
- Review final code and screenshots before release. Normal dev→main PR merge + sync dev; automatic iOS/Mac TF packaging; deploy changed Web to production and verify assets. No App Store submission or TF polling.
- Final evidence/results will be appended after execution, not preclaimed.

## Verified outcomes (2026-11-11)
- Web production build, 11 search/time unit tests, locale tests, browser fixture regression passed. Same-query background refresh preserves result DOM/scroll; updated/deleted records still refresh.
- Native search/date/excerpt/count tests and Markdown/TextKit offset tests passed. Production Mac build passed.
- iPhone and iPad isolated UI tests passed: immediate empty state, centered zero state, count, completed/image/long navigation, hidden tail match, and stable post-navigation scroll. Final compact three-line previews captured; iPhone actual dark appearance verified.
- Mac built-app UI inspected: light/dark results, empty and zero states, real scrollbar clear of timestamp, toolbar spacing, All icon, hidden tail located.
- Ranking unchanged: literal, full pinyin, consecutive initials, then recency within rank.
- Screenshots use fictional isolated data. Physical-device acceptance remains the user's TF pass.
- Evidence directory: /Users/haer/.codex/visualizations/2026/11/05/01a1ac56-c8f9-73c1-b1d6-a3f7776c2997/search-walkthrough-20261111/
- Main captures: web-results-many.png, web-results-last.png, web-zero.png, web-focus-first.png, web-focus-last.png; mac-results.png, mac-results-dark.png, mac-scroll-results.png, mac-toolbar.png, mac-tail-located.png; iphone-walkthrough-results.png, iphone-walkthrough-dark-results.png, iphone-walkthrough-tail-located.png; ipad-walkthrough-results.png, ipad-walkthrough-tail-located.png.
- Browser headless screenshots do not expose macOS overlay scrollbar itself; clearance/style assertions passed. Mac native screenshot includes the actual scroll indicator.
