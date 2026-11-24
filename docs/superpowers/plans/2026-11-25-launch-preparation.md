# Synca 1.2 launch preparation — 2026-11-25

Authorized: prepare a quieter App Store product-page header, research functional ASO in three locales, improve official-site SEO, add real Windows downloads, enable email login on production Web. No App Store review submission or live identity changes in this step.

## Decisions
- Header: no standalone logo or slogan; preserve whitespace and a restrained visual relationship with quick capture/sync. Show a draft before replacing the current asset.
- ASO: prioritize accurate functional queries (notes, file transfer, cross-device sync), preserve Synca brand, disclose Pro boundaries, do not fabricate search volume or rankings.
- SEO: real robots.txt/sitemap responses, canonical/hreflang, structured metadata/social cards, crawlable three-locale downloads. Preserve app routes.
- Windows: publish fresh production x64/ARM64 portable packages with SHA-256 and immutable URLs; retain the native-runtime verification boundary (ARM64 tested, x64 package checked).
- Email: existing email sign-in and binding routes; Apple remains first. No new registration flow. Desktop first-paint availability preserved.

## Work and acceptance
1. Capture existing ASC metadata and header; compare EverBond precedent; prepare editable artwork, crop preview, geometry manifest.
2. Prepare title/subtitle/keyword and description drafts, accurate counts, sources, and release checklist.
3. Test capability changes, browser login methods and disabled/error states; compile backend and Web.
4. Validate three-locale website at desktop/tablet/phone widths; check links, semantics and crawler file content.
5. Publish immutable Windows artifacts, backend/Web and marketing files with existing rollback safeguards. Verify live capability, email form, crawler files, download ranges and checksums without creating real accounts.
6. Report live changes separately from pending store artwork/metadata approval.
