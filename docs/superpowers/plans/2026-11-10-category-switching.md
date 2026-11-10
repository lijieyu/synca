# Category switching performance

Scope: Mac, iOS and Web local switching only; preserve layout, selection, auto-focus and deletion behavior. No release requested.

1. Capture isolated Web warm-switch latency and image remount behavior using fictional records. Assert switching needs no list requests and cached images do not restart with a new object URL.
2. Reuse protected Web image URLs within the existing bounded/session-scoped cache; revoke on eviction/logout. Memoize unchanged message rows with stable callbacks. Preserve expired-attachment checks.
3. Mac: keep the scroll container identity across category changes; cancel stale scroll tasks and set the destination without a delayed reset. Keep text-collapse layout revision behavior. Mac and iOS: cache decoded thumbnails with a bounded, token/generation-scoped memory cache and initialize warm image views from it. Keep the existing iOS category/collapse scroll identity: replacing it failed the repeated last-row collapse regression.
4. Verify Web before/after, cache expiry/session invalidation, native thumbnail reuse, native builds, iOS last-row collapse and image scrolling regression. Run one simulator at a time, shut it down after verification.
5. Report measured results and limits. Do not claim physical-device performance from simulator tests.

## Local verification

- Web production build passed; 84 Vitest tests and 3 Node tests passed.
- Isolated Web browser fixture: 12 switches, zero extra list requests, one media fetch, stable image object URL, no script errors. Two-frame callback median was 33.3 ms before and 32.5 ms after: this does not establish a meaningful total-page speedup. Stable image reuse is verified.
- Native thumbnail test passed: decoded image identity reused, cache clear and account isolation checked. One fixture measured approximately 70 ms cold versus 0.1 ms warm; this measures thumbnail retrieval only.
- Final Mac Production build passed (`/tmp/synca-perf-mac-safe.log`).
- Final iOS isolated UI suite: all 5 tests passed, including repeated last/penultimate text collapse, image bottom scrolling, category switching and palette (`/tmp/synca-scroll-perf-safe.xcresult`). Simulator shut down afterward.
- iOS container reuse was rejected after intermittent collapse regressions; original iOS scrolling code remains unchanged. Only Mac uses persistent scroll identity.
- No PR, merge, production deployment or TF action performed. Real-device perceived responsiveness remains for acceptance.
