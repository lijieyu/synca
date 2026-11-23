# Desktop polish preview — 2026-11-24

Scope: approved Web/Electron refinements. Production Web and Mac TestFlight wait for user acceptance. Existing clipboard fix is retained. No backend, iOS, production database or email delivery changes.

## Changes

- Desktop account trigger opens the exact agreed menu; static identity, Settings, Feedback, About Synca, Sign Out. Footer plan subtitle removed; separate settings gear retained.
- Apple authorization waiting/cancel uses a stable centered slot. Email login copy shortened, monochrome login controls preserved.
- General selects reserve 34px for the chevron; category drag/delete controls remain visible.
- Feedback removes image heading/always-visible limits, keeps validation; action follows content with comfortable padding. Official Xiaohongshu website logo identifies contact link. About registration line removed.
- AI connection tutorial expanded above copy instructions. Primary app actions retain purple; text links use blue.
- Shared desktop action token: 36px minimum height, 13px/20px type, 8px radius. Dialog/form/download/account/AI actions share it; toolbar and composer icon controls are 36px. Navigation rows, color swatches and login primary controls retain their appropriate roles/sizing. Mobile touch controls are not reduced.
- Native menu close/hide roles added. Existing close interception retains the window; background refresh interval and badge updates untouched.

## Evidence

- Web and Electron renderer builds passed. Electron build is not a packaged TF release.
- 17 Apple/email auth tests passed; 13 locale/desktop variant/MAS configuration checks passed.
- 14 existing sidebar/category/Markdown helper tests passed; clipboard bridge/Web fallback suites passed.
- Browser interaction checks: exact menu order, keyboard open/Escape, menu-to-feedback navigation, About registration removal, email-code step and help expansion.
- Apple idle vs pending at 640x500: brand y=61.6015625 and button-group y=244.6015625 unchanged; cancel centered at x=307, width=26 in 640px viewport. Email help expansion left login button y=296.9921875 unchanged. These checks used an isolated local fixture with a pending Apple SDK stub; no real Apple authorization was submitted.
- Visual checks: 1100x760 Chinese light, 640x500 English dark and Chinese light, 390x844 mobile settings. Desktop feedback add-image/submit measured 36px. General select height=36px, right padding=34px.
- Independent read-only review found no blocking issues. Its two sizing findings were corrected: composer grid tracks now 36px; settings close/back min-width matches 36px.
- Native shortcut behavior still requires acceptance in the next packaged Mac build; preview cannot exercise native menu accelerators.

## Deployment

Frontend-only updater: `scripts/deploy-preview-web.sh`. It discovers the single active preview service, backs up prior web assets, retains old hashed chunks for open tabs, publishes HTML atomically, and checks production index/link unchanged.

Active preview wrapper is `synca-preview-email-tf` (the older `synca-preview` process is stopped). Frontend updated at `/opt/synca-preview/releases/tf-20261122-ceef58ed-email/web`; release backup `/opt/synca-preview/web-releases/20261123T170923Z-b61dd3c-web`.
Authenticated preview HTML/assets/logo fetches passed. Existing gate and restricted preview email identity remain intact. Production Web link stays `/opt/synca/releases/20261123T080605Z-17bd510/web`, index SHA256 `556fe2a145879af92fee5bb25dce8c8bca997deaad124b937957296a9ff8a207`.
