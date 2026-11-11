# Search polish acceptance contract

User-requested corrections, same scope on iOS, iPadOS, macOS and Web. No releases or poster replacements until QA.

- iOS/iPad toolbar: search first in trailing group. Mac: plain search icon. Web: mouse-opened search restores focus without spurious keyboard outline; real keyboard focus stays visible.
- Desktop search: stable 640 x 560 default, Web capped to viewport. Keep mobile navigation. Native placeholder/prompt/empty wording is canonical across zh-Hans, zh-Hant and en.
- Web search field: neutral filled background, no focus outline or border. Input caret and accessibility label remain.
- Results: highlight all mapped literal, pinyin and consecutive-initial matches; keep late matches visible in preview. Compute transliteration off UI thread and retain account-local caches.
- Original record navigation: start a restrained 120ms fade-in on first anchor, fade out after 900ms over 400ms; keep lazy layout correction and user-interruption guards; respect reduced motion.
- Remove all-category leading icon on three platforms.
- Approved follow-up: retain query in current signed-in view memory, select all when reopening; clear on logout/account switch or process/page restart. No persistent storage or query history.

Verification: range tests incl Unicode/late phonetic/filename; browser focus, layout, query retention and navigation fixture; iOS search UI fixture and Mac isolated build/capture; one simulator at a time. Physical-device final acceptance remains with user.

## Verified locally
- Web build and 9 search/index/worker tests passed; three-locale parity passed.
- Browser fixture passed window dimensions, border removal, mouse Escape restoration, keyboard Tab focus, query retention/select-all/reload reset, mapped initials highlighting, and existing navigation/late-image/live-change checks.
- iPhone UI fixture: cancel preserves position; completed, long and delayed-image targets remain visible; reopen replaces selected query and relaunch clears it. Final single-line input-height assertion passed.
- iPad UI fixture: trailing entry, single-line search field, retention/select-all and relaunch reset passed.
- Mac isolated app: plain entry, 640 x 560 search, mapped highlights, Escape, retained query selected on reopen, replacing query and navigating to image/category inspected with CUA.
- Final iOS and macOS builds passed after the input-method clearing safeguard. Web keyboard focus regression found during review was fixed and retested.
- Screenshots: `/Users/haer/.codex/visualizations/2026/11/05/01a1ac56-c8f9-73c1-b1d6-a3f7776c2997/search-polish-20261111/`.
- Real-device acceptance remains pending; marketing posters are unchanged.

## Approved follow-up and final checks
- Preserve literal > full pinyin > consecutive initials ranking, newest first within rank. No category grouping or sorting change.
- Mac result rows use whole-row hover/pressed background; completed results use filled check circles; category names include resolved palette color on all platforms.
- Final native search tests, Web nine search/worker tests and three-locale parity passed.
- Final iOS and Mac isolated builds passed; Web production build and full browser navigation/focus regression passed.
- Final Mac result rendering inspected with fictional records; screenshot saved as mac-results-final.png.
- User authorized normal PR merge for automatic iOS/Mac TF packaging. No Web production deployment requested in this follow-up.
