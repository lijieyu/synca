# Synca search release and marketing refresh

## Authorized scope
User requested TF for the finished three-client search, refresh existing approved App Store artwork with the search entry, and continue the accepted website direction autonomously. Keep the accepted poster compositions, fictional data and three locales. Preserve the existing Web root, login, sessions and records. No App Store review submission or screenshot upload requested.

## Delivery choices
- Search: dev → main PR, existing automatic iOS/Mac TF workflow; Web-only code deployment. No backend/database changes.
- Artwork: new version alongside the accepted set, replacing only necessary verified app header surfaces; retain originals and disclose compositing. Re-render iPhone at a currently accepted large-device slot, not stretch old exports. Validate all platforms/locales.
- Website: standalone `/home/` introduction in the existing Web public assets; no redirect at `/`. Simplified Chinese, Traditional Chinese and English. Real privacy-safe app captures, concise product/transfer/AI benefits, App Store and Web entry links, verified ICP and police registration. Private preview first; production activation remains separate from this search release.

## Search release evidence
- PR: https://github.com/lijieyu/synca/pull/76 — merged, main commit `19feb2804669d267d419ccb3d7c05286023793f9`.
- Dev fast-forwarded to the same merged commit. iOS and Mac use existing automatic TF workflow; processing/distribution not independently polled.
- Web release: `20261110T183327Z-19feb28`.
- Live root references `index-CtLrdL_T.js`, which references the current search-bearing list chunk; list and pinyin worker resources returned HTTP 200. `/health` OK.
- Fresh 96 Web Vitest + 3 Node tests, build, native search/index/sync/cache/Markdown and three-language checks passed before merge. UI evidence is documented in the search implementation plan.

## Remaining acceptance
- TestFlight real-device search/navigation acceptance.
- Review updated poster set; no automatic App Store upload.
- Review website preview before production activation.

## Artwork refresh
- New set: `/Users/haer/.codex/visualizations/2026/11/05/01a1ac56-c8f9-73c1-b1d6-a3f7776c2997/release-1.1.0-search/`.
- 36 posters: 4 themes × 3 platforms × 3 locales. Existing copy, compositions and fictional records preserved; actual native search-header regions composited into previous verified captures. Full originals and source coordinates retained.
- iPhone 1320×2868; iPad 2064×2752; Mac 2880×1800. Official Apple specifications checked 2026-11-11; 36/36 format and geometry checks passed. New set remains draft pending visual acceptance, not uploaded/submitted.
- Archives beside set: `Synca-1.1.0-search-posters.zip`, `Synca-1.1.0-search-editable.zip`. Previous accepted set is unchanged.

## Website implementation
- Static three-language `/home/` under `web/public/home/`; no JavaScript, account APIs, storage changes or root redirect.
- Main slogan follows the approved “灵感记录，即刻同步”. Localized privacy-safe assets include updated search entries. Product, transfer and external-AI explanations remain concise.
- 12 locale/viewport/appearance combinations passed with and without JavaScript. Independent review found preview-host assets/service links crossing its auth boundary; fixed by self-contained `/home/assets/` and absolute production service links. New test assertions pin both boundaries.
- Preview-only deployment script `scripts/deploy-home-preview.sh` stores rollback backups outside the public directory and checks production app/config hashes.

## Preview outcome
- Public review URL: https://synca-preview.haerth.cn/home/ (three locales, no login required, noindex/nofollow/noarchive).
- Preview artifact: `/opt/synca-preview/home-releases/20261110T184150Z-be0d67a`; production config and app index hashes unchanged.
- Fresh anonymous browser verification: 12 locale/viewport/appearance cases with JavaScript enabled and the same 12 disabled, all passed; image loads, navigation, keyboard skip link, no horizontal overflow and zero cookies verified.
- Online screenshots saved under the visualization workspace `website-20261111/`. No production website activation, App Store asset upload or review submission performed.
