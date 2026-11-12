# Synca marketing page

## Scope and design

The accepted warm neutral / restrained purple demo is implemented at `/home/`. Main message: **灵感记录，即刻同步**. Sections: real product capture, record/organize/sync/search, file transfer, external AI, download. The page uses static HTML and one shared CSS file; no JavaScript, analytics, external fonts, cookies, local storage, or API calls. The existing `https://synca.haerth.cn/` login/application remains the Web entry, with no auth or data changes.

Locales are independently indexable pages with canonical and hreflang tags: `/home/`, `/home/zh-Hant/`, `/home/en/`. Language links do not alter app language preferences. Traditional Chinese legal/support links follow the app's current simplified Chinese legal routes. Download links use verified App Store ID **6761647007**. The page links the existing `/ai/` guide, privacy, terms, and support pages using absolute production URLs so a separate preview also works. All local page assets, including branding, live under `/home/assets/` to avoid preview application gates.

Responsive choice: desktop presents real Mac and iPhone captures together; narrow screens prioritize the readable iPhone capture. Dark appearance changes page surfaces and typography; product captures remain truthful light-mode screenshots. Reduced motion disables transitions. Native links, visible focus, first-tab skip link, headings, image alternatives and 44px primary/language controls are included.

## Source assets and evidence

- Accepted source: `synca-home-demo.html` in the task's visualizations folder.
- Approved messaging: app-store-release `references/products.md`, plus the three-locale `release-1.1.0/copy.json`.
- Current native images: `release-1.1.0-search/captures/`, native demo content with the actual search-control header region composited from the verified new native build. This is **not** a new complete live screenshot or proof of real synchronization. See that release folder's `search-composite.json` for region provenance. Only the search region changes; the rest of the privacy-safe fictional content stays as previously accepted.
- AI images: original approved `release-1.1.0/captures/gpt-main-*.png`, showing a real authorized demonstration conversation. The original personal sidebar/account was excluded; the accepted rendering-only removal of Store Demo title prefixes remains. No new user account reads or writes were made for this website.
- WebP assets preserve these captures, downscaled for web delivery at quality 88, with no content redrawing. The entire website directory is under 0.8 MB across all three locales; one locale loads only its own images. No poster headline imagery is used as app UI.
- Footer numbers and destinations were checked in a live Playwright browser against `https://haerth.cn/` on 2026-11-11 (Beijing): `浙ICP备2026013056号` → `https://beian.miit.gov.cn/`; `浙公网安备33010602014403号` → `https://beian.mps.gov.cn/`. The accepted demo's registration icon is reused.
- App Store was opened live and resolved to “Synca · 灵感记录 即刻同步”, ID 6761647007.

## Claims and constraints

Search copy covers record text and filenames, pinyin and initials. It does not claim OCR or file-content indexing. AI explicitly requires Pro, an external compatible MCP client and authorization; there is no bundled model claim. File transfer does not promise lossless/original images, perpetual attachment storage, unlimited capacity or any specific price. Retention and allowances defer to current in-app information.

## Local preview and validation

From the repository root:

```sh
python3 -m http.server 4181 --bind 127.0.0.1 --directory web/public
```

Open `http://127.0.0.1:4181/home/`. A plain static preview serves only marketing assets; `/` and legal/API routes are supplied by the existing application in an integrated deployment.

`web/tests/home.browser.cjs` exports an async function that accepts a Playwright Page and optional `{baseURL, screenshotDir}`. Run it using an existing Playwright installation/context; no package/dependency changes are needed. It checks 12 locale/viewport/appearance combinations, all images and anchors, canonical URLs, no horizontal overflow, one H1, no runtime scripts, original Web-entry links, minimum primary/language target size, exact registration text, first-tab skip link and locale navigation. It throws on failure. For example:

```js
const checkHome = require('./web/tests/home.browser.cjs');
await checkHome(page, { baseURL: 'http://127.0.0.1:4181', screenshotDir: '/tmp' });
```

Latest local verification: all **12** combinations passed (1440 light, 390 light, 320 dark and 768 dark in each locale); no page errors. The same 12 cases also passed with JavaScript disabled and include checks that local assets remain under `/home/` and service links are absolute. Final screenshots: `/tmp/home-zh-Hans-1440-light.png`, `/tmp/home-zh-Hans-390-light.png`, `/tmp/home-en-320-dark.png`.

## Deployment boundary

No deployment or root-route change is part of these page files. Vite copies `web/public/home/` into `dist/home/`. The marketing directory can also be served independently at a `/home/` alias. Any server preview should remain noindex and must not replace the live app directory, change authentication, or touch user data. The coordinating agent owns release/preview integration and verifies those boundaries.

## Verified hosted preview (2026-11-11)

https://synca-preview.haerth.cn/home/ is live as an independent public, noindex preview. Anonymous browser verification passed all 24 cases (12 with JavaScript and 12 without), including resources and locale links. No cookies were set. The original production app index and nginx configuration remained byte-identical during this preview deployment. Activate `/home/` in production only as a separate release after review; the existing `/` app remains the default entry.

## Fifth search poster / website update (2026-11-11)

Added a localized search section and real Mac search screenshots in all three locales. Search captures and notes captures are from current production native views in an isolated fictional-data fixture, without accessing a real account. Other accepted app captures only received current toolbar pixels; composition provenance is recorded in `release-1.1.0-five/capture-evidence-20261111.json`. Current marketing artwork contains 45 exports: five scenes for three platforms and three locales.

Latest verification after this update: 12 locale/viewport/appearance combinations passed with zero page errors. Preview deployment remains separate from the production root application. Asset-size statement above describes the earlier set, not this expanded set.

## Production publication and link behavior (2026-11-12)

`bash scripts/deploy-home.sh` publishes only `/home/` and its locales through an independent nginx alias and immutable static release. It checks the existing app index hash before and after; it never replaces the root app, changes authentication/storage, or deploys backend/native code. The production homepage remains an explicit `/home/` URL; no visitor or session redirect is used.

All links to other pages (download, Web app, AI guide, legal/support, registrations and locale pages) open a new tab with `noopener noreferrer`. The top download link goes directly to App Store. Product-section and skip anchors remain within the page.

## Public tutorial and navigation refinement (2026-11-12)

Language links switch within the same tab. Download, Web app and footer page links retain new-tab behavior. The product navigation link and marketing search section are removed (App Store search artwork remains). The AI link opens a localized native HTML dialog with static instructions, copy feedback, expandable instruction text, Escape dismissal and focus restoration. It performs no authentication or connection-state requests. `/home/guide.js` is the only runtime script.
