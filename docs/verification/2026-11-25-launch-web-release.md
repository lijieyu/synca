# Launch preparation — public Web and downloads

User scope: prepare a quieter product-page header and functional ASO; improve site discoverability; publish Windows downloads; enable production Web email login.

## Published and checked

- Code PR123 → dev and PR124 → main merged; release merge `36f66383348c1db9d9d414671bc75f61c14b598e`. dev synchronized to main. Product implementation revision `dbb2c3a`.
- Backend and Web release: `/opt/synca/releases/20261124T172125Z-dbb2c3a`. Deployment performed consistent SQLite backup, existing additive migration check, backend restart and health validation. Existing account/session/record data preserved; no mail credentials or global email settings changed.
- Homepage release: `/opt/synca/home-releases/20261124T172226Z-dbb2c3a`. Independent alias, root app index unchanged during homepage deployment.
- Windows immutable public files: `/downloads/windows/1.2.0-20261125/Synca-1.2.0-Windows-{x64,arm64}.zip` and `SHA256SUMS.txt`. Full public HTTPS byte hashes matched both pinned artifacts. Unknown artifact returned 404. See separate Windows provenance/verification record for runtime limitations and unsigned portable status.
- Anonymous production browser: headerless `/auth/capabilities` returns `email:true`; Apple first, email entry visible, clicking opens the real email form. No mail sent or account created by this check; it does not reverify inbox delivery.
- All three live locale pages contain the current Windows URLs and correct canonical. robots.txt is `text/plain`, sitemap.xml `application/xml`, neither is SPA HTML. External range requests for both ZIPs return 206 and the correct ZIP signature.
- Evidence: `/Users/haer/Documents/Codex/2026-11-25/synca-launch/live/verification.json`, Web entry/form screenshots and website screenshot.

## Verification reused and performed

Backend email/configuration/delivery tests 41; email client tests 13; five browser capability cases. Backend and Web production builds passed. Five SEO/routing tests and twelve locale/viewport/theme homepage cases passed. Windows package identity/integrity checks and ten compatibility/isolation tests passed. A read-only review found no P1/P2 issues.

The first download deployment detected old SPA bytes immediately after nginx reload and automatically restored the config; no website link was published at that point. Bounded exact-byte readiness checks were added because nginx workers reload asynchronously. Retry succeeded, both public packages were fully hashed, and subsequent homepage/app releases preserved downloads.

## Prepared, not submitted

ASO analysis and three-locale copy are in `docs/marketing/`. Product header is an opaque 3840×1646 draft, with SVG and manifest under `docs/marketing/header-2026-11-25/`. No App Store name/keywords/header were changed and no review submitted.

Google Search Console was opened in the user's existing signed-in browser. A URL-prefix property for `https://synca.haerth.cn/home/` requires an HTML ownership file. The file was downloaded and prepared locally. Automatic approval rejected committing/deploying it because ownership/access authorization was not explicit. User confirmation was requested; the token was not published. Sitemap submission and ownership are therefore not yet complete. Bing ownership/submission and actual Google indexing/rankings are also not confirmed.
