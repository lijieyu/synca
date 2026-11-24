# 2026-11-25 overnight release and App Store draft

## Scope

User authorized TF submission, launch draft preparation, latest official website updates and safe email-deliverability investigation. No App Review submission or public App Store release is authorized by this task. Public Web email sign-in remains enabled as explicitly requested on November 25.

## Validated changes

- Desktop search header inset fixed without changing modal dimensions, pinyin/IME behavior or search scope: 15 browser cases and 14 related unit tests passed.
- iOS follow-system appearance, short-feed initial gap, single secondary category-management icon: simulator regression evidence is in `2026-11-25-search-appearance-feed-polish.md`. Long-feed bottom positioning and draft preservation passed. Existing tests were reused for unchanged code; simulator was shut down.
- Windows 1.2.0 (88) x64/ARM64 ZIPs: exact package files/hash/PE/production identity verified; 15 unit checks and 12 website browser cases passed. No new Windows VM execution claimed.
- Email acceptance tracing: no recipients, codes, credentials or provider text logged. 200 backend tests passed across full-suite and corrected isolated AI-suite invocation; 2 existing skips. Provider acceptance does not prove inbox placement.
- MAS release gate now reflects authorized public Web email availability; 3 gate tests passed. Historical backend compatibility baseline is explicitly labelled, not presented as current deployed code.
- Independent review found no P1/P2 blockers in appearance, feed layout or search CSS.

## App Store Connect draft saved

App `6761647007`: created iOS **1.2.0 准备提交** and macOS **1.2.0 准备提交**. Both retain the existing automatic-after-approval release selection; no review action taken. No build was selected: the latest TF has not been checked or claimed installable.

Saved English, Simplified Chinese and Traditional Chinese descriptions, promotional text, keywords and platform-specific release notes. Saved shared App Information names/subtitles from candidate A. The UI accepted full Chinese keywords (69/65 characters), with no byte-limit fallback needed. Source is `docs/marketing/2026-11-25-store-metadata.json`.

Saved updated reviewer notes on both platforms explaining Apple/email sign-in, bidirectional linking, free limits, Pro and optional external MCP clients. No reviewer password or private OTP was inserted. Existing contact information, pricing, availability, privacy declarations and ratings were preserved.

Three iOS header associations were replaced in the new draft; old assets remain in the library. Uploaded RGB 3840×1646 v3 files have no separate logo/decorative line and preserve the devices as requested. Full-size uploaded artwork was opened and visually checked in ASC:

- zh-Hans: asset `c1000019-3068-8b9f-8f2d-0ae164053ed5`, thumbnail `ME-Rw-AJSfHO0QSfEGoOLA`.
- zh-Hant: asset `71000019-3068-8b9f-8f28-5495a9f57eb5`, thumbnail `GRZARu4qcufIH8a2QTE7ug`.
- en-US: asset `d2c00019-3068-8b9f-8f23-bd4981bb25f2`, thumbnail `pweSmz3yeNoKHHbcvM1frQ`.

English description and header association survived a full page reload. Other localizations were reselected and read back; Mac notes/release notes match the saved source.

**Remaining submission checks:** ASC device preview showed the default product layout without the header, so responsive header cropping is not asserted verified. Existing 1.1.0 screenshot sets remain; especially Mac screenshots need current Electron UI review/replacement before actual submission. Device artwork was intentionally preserved per the user's request. These drafts are prepared for user review, not declared submission-ready. A final validated public build and any required review access must be confirmed before submitting.

Draft links:
- https://appstoreconnect.apple.com/apps/6761647007/distribution/ios/version/inflight
- https://appstoreconnect.apple.com/apps/6761647007/distribution/macos/version/inflight

## Email result

Authentication is configured and passes in observed Outlook headers. Two inspected current-domain messages were classified SCL 5 by Outlook; the forwarded sample was marked notspam by iCloud before forwarding. Root cause inside Microsoft's filter remains undisclosed. DNS/template/domain churn, paid IP purchase and support messaging were not performed. See the redacted deliverability report for evidence and follow-up material.

## Delivery

To be filled after verified merge and deployment. TF shorthand uses the normal main-branch automatic workflows; do not manually start duplicate builds or poll TestFlight.
