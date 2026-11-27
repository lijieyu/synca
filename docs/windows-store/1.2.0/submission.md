# Stable Store submission — 1.2.0 (89)

**Current status (2026-11-27 23:04 Asia/Shanghai): submitted successfully; Partner Center shows “正在认证”, preprocessing in progress. Certification and public release are not yet complete.**

User changed the first Store release to the mature website version on 2026-11-27. Publisher display name selected: Jieyu Li. Registration was completed on the user's MacBook; authenticated access from the Mac mini is now established.

## Source and packaging
- Immutable website release: `1.2.0-20261125-r3`, both SHA-256 values pinned in `desktop/store/stable-1.2.0.mjs` and matching the original website publication script.
- Original executable, renderer, original main and all modules remain unchanged. ASAR package main points to a minimal Store adapter; the adapter isolates userData/sessionData at `Synca Store`, compatible with the later 1.2.1 Store profile. The full allowed delta is recorded in build-evidence.json.
- No website auto-updater exists in 1.2.0. Microsoft Store owns updates. No 1.2.1 feature code is imported or rebuilt.
- Package version 1.2.0.0. `runFullTrust` supports the existing Electron desktop runtime, tray, clipboard and user-selected file dialogs; no new screenshot permission/feature.

## Build and evidence
Workflow `.github/workflows/windows-store-stable.yml` runs native x64/ARM64 packaging and stable UI/profile checks without building current Web/UI code. Default is explicit CI identity. Real identity JSON is held in repository variable `SYNCA_STORE_IDENTITY_JSON`; set `SYNCA_STABLE_STORE_FORMAL=true` only after assigning the verified Partner Center identity, then a scoped dev push builds formal-identity packages. This avoids depending on a new workflow already existing on main. Alternatively use manual formal_identity once dispatch is available. No build submits or publishes automatically.

The Windows fixture uses instrumented copies, synthetic accounts and a local backend. Source preservation is checked on the uninstrumented package. Formal Microsoft-signed installation, production login and Store update behavior require separate evidence.

## Remaining release gates
- Assigned identity and approved localized names are recorded below; reservation is complete.
- Use only these versioned listing files and 1.2.0 screenshots; current 1.2.1 listings are not valid for this release.
- Verify live privacy/support URLs and supported reviewer access. Private reviewer credentials must never enter git or public artifacts. Do not invent an authentication bypass.
- User personally completes legal declarations, any further identity verification and developer agreement.
- Submit formal-identity package and retain submission ID and actual certification result.
- After the app is publicly available and actual Store install/login/basic operation succeeds, update the website's primary Windows link to the real Store URL. Keep current x64/ARM64 portable links as alternatives. No homepage switch merely because a package uploaded successfully.

## Partner Center check (2026-11-27)
Authenticated access on the Mac mini now works using the existing personal Microsoft account session. The account overview contains no products. Microsoft reports exact name **Synca unavailable** and **Synca Notes available**. The alternative is awaiting the user's naming decision; no product/name has been reserved and no identity or Store product ID has been issued.

Live privacy/support pages return successfully, but currently describe Apple-only login/platforms. Before submission, update the public text to include Windows/Web and email authentication plus existing file uploads; do not publish 1.2.1-only feature descriptions as part of the stable launch. Current dev legal content includes Collections/Scratchpad and must not be deployed wholesale for this purpose.

## Validation refinement
Review fixes isolate the fixture under temporary AppData, own and await the backend process, and test two independent launches. The builder unpacks the actual final MSIX and verifies exact manifest plus executable/ASAR/build-info bytes, recording package SHA-256. Screenshot inspection caught a weak assertion that could match unsent composer text; f26fa90 now clicks Send and requires the record in the message list after reload. Earlier create/read evidence is superseded by this stricter run.

Final technical validation: [run 46001240270](https://github.com/lijieyu/synca/actions/runs/46001240270), commit `f26fa9089a1daf5e515902712ac7191233561208`, completed **success** on native x64 and ARM64. Both perform final MSIX content verification and two consecutive isolated runtime checks, including send/reload persistence. Actual Chinese light/dark and English screenshots archived locally at `/Users/haer/Documents/ChatGPT/Synca/acceptance/1.2.0-store/index.html`. Packages still use CI identity and are not submittable. Microsoft-signed installation and certification remain unverified.

## Name reserved and official identity
On 2026-11-27 the user approved **Synca Notes**. Partner Center successfully created the draft MSIX/PWA product. Assigned public identifiers, read directly from Product identity:
- Store ID: `9PJ7VZ48QM81`
- Package Identity Name: `JieyuLi.SyncaNotes`
- Publisher: `CN=EFB41A73-FB6E-4C6E-9E94-53511FFD42FF`
- PublisherDisplayName: `Jieyu Li`
- English display name: `Synca Notes`
- Package Family Name: `JieyuLi.SyncaNotes_n7haejrbvpnsy`

Chinese localized name remains under discussion. The assigned Store URL is not evidence of public availability; the product is still a draft and no submission exists yet.

## Approved localized names — reserved successfully
All three names were approved by the user and reserved under the same product on 2026-11-27:
- en-US: **Synca · Notes & File Transfer** (also set as dashboard name)
- zh-CN: **Synca · 笔记与文件传输**
- zh-TW: **Synca · 筆記與檔案傳輸**
Original Synca Notes reservation remains; do not delete/recreate the product. Package identity and Store ID are unchanged. `desktop/store/identity.production.json` contains only the public, assigned identity and approved default English package name. Localized Store listing names must be selected in their respective listing pages; reserving a name alone does not publish a listing.

## Formal build and listing draft — 2026-11-27

Formal native Windows run [46006176148](https://github.com/lijieyu/synca/actions/runs/46006176148) at `7c9ad9b172239237a3e8c2c5cb6e31745cf83aee` succeeded on x64 and ARM64. Downloaded packages were independently checked against build evidence and their embedded manifest identity:
- x64 SHA-256: `c3d98960a49fcef7e51389b3f1ca92471586bcf464c24b81acb535099a9656a6`
- ARM64 SHA-256: `8c5ff197816ee4b0f18a8af43ff2a8d3e873fa1eb984567b8b71cc140015f991`
- Both use the assigned Name/Publisher, version `1.2.0.0`, and their correct architecture. These are unsigned Store-upload artifacts; no Microsoft-signed installation claim is made.

Submission draft `1152921505702525382` exists. English, simplified Chinese and traditional Chinese listing pages were saved with their approved localized names, version-correct descriptions, short descriptions and real Windows screenshots. Partner Center reports Store listings **Complete**. First-submission release notes are blank. Traditional Chinese currently uses the English UI screenshot; no localized screenshot claim is made.

x64 upload passed ingestion with only the expected `runFullTrust` restricted-capability review warning. ARM64 bytes uploaded and its package appears in the device table with the same warning; the uploader still reports “Analyzing package” at 99%, so final save is not yet verified. Desktop is selected; all other device families and automatic future-family availability are disabled. Product is still a draft, not certified or published. Website links remain unchanged.

Browser follow-up is waiting for the user to release the Mac mini foreground browser. The independent tab connection reports unavailable; no certification submission was attempted. Remaining forms: availability/pricing, properties/privacy links, age rating, review notes and final submission.

## Submission preparation completed; IARC acceptance pending

On 2026-11-27, after refreshing the stalled upload UI, both packages showed **Validated** and the package section saved as **Complete**. Store listings, Properties and Pricing/availability also show Complete. Price is CNY 0 for the default 240-market group, public/discoverable, release as soon as certification passes. No paid Store purchase or Microsoft IAP was added.

Properties: Productivity; personal information = yes; official English privacy/support URLs; existing non-Microsoft commerce declared. No accessibility-certification or embedded generative-AI claim was made. OneDrive automatic data backup and game recording/broadcast declarations are disabled. Desktop-only distribution remains selected.

The runFullTrust justification was shortened to 419 characters to satisfy the 500-character limit and saved. Additional Testing Info contains the actual version scope, email verification sign-in steps and basic record/category/search/restart checks. No reviewer credentials or authentication bypass were added; production reviewer login and Pro-path access are not claimed verified.

IARC questionnaire completed and preview generated: other app; no bundled rated content, no native interaction between users, no promoted online content, no restricted products/location sharing/rewards/browser/news; digital purchase yes, random purchase no. Preview: global/Microsoft/PEGI 3+, ESRB Everyone, Brazil 14. The unchecked checkbox explicitly accepts IARC terms and declares legal adulthood. **The user must personally accept and save this step.** Certification has not been submitted.

## Public legal page correction — deployed and verified

Live stable source was read from `/opt/synca/releases/20261126T050231Z-f03b149/backend/dist/src/legalPages.js`; original SHA-256 `31b6db3685d2c74e647ec020cf7e2215b78cf38fd032ee80c1aff782671445c3`. The patch in `legal/production-module.patch` adds only existing platforms, email login and image/file storage to the six English/Chinese policy, terms and support pages. Existing quota, price, retention and liability text is unchanged. No 1.2.1 code was deployed.

First attempt copied only dist and failed module resolution (`dotenv` missing from the new release ancestry), causing a brief service interruption; the health-check rollback restored the original release and health returned OK. Root cause was reproduced without starting a service. The release was repaired with the original package metadata and a symlink to its existing locked dependencies; all 144 static import resolutions passed before retry.

Final active copy: `/opt/synca/releases/20261127-store-legal-stable/dist`; only `src/legalPages.js` differs. Module SHA-256 `95d1d0c3c94bd2e98c4778d647f8e0cfcf061220fad33bbea42728a8873a8b9b`. Original release retained for rollback and dependency reuse. All six public HTTPS pages and health passed after successful activation. Evidence: `/Users/haer/Documents/ChatGPT/Synca/acceptance/1.2.0-store/legal-20261127/verification.json`. Current dev legal source received the matching factual corrections for the next normal release. No nginx override or website download-link change.

## Certification submission receipt — 2026-11-27 23:04 Beijing

The user personally accepted and saved the IARC terms/adulthood declaration, then explicitly asked the agent to complete submission. Readback showed Age ratings **Complete**; Pricing/availability, Properties, both packages and Store listings were also Complete. Both MSIX files were **Validated**.

The agent selected **提交进行认证**. Partner Center transitioned from draft to **正在认证** and displayed:
- Submission: complete.
- Preprocessing: in progress.
- Certification: not started.
- Publishing: not started.
- “产品在通过认证后立即开始发布。”
- Product submission: **正在认证 (Submission 1)**.

Identifiers: Store product `9PJ7VZ48QM81`; submission `1152921505702525382`; MSIX `1.2.0.0` x64/ARM64 from website 1.2.0 (89). Receipt was visually checked in Partner Center and a screenshot is included in this chat's browser tool evidence. Dashboard: https://partner.microsoft.com/zh-cn/dashboard/products/9PJ7VZ48QM81/overview

No additional agreement or personal verification was presented for this submission. The Microsoft feedback survey was not submitted. No website download link was changed. Microsoft-signed installation, production account smoke testing, Pro reviewer access and update verification remain unverified; do not turn this submission receipt into a claim of approval or install readiness. Reviewer notes describe normal self-service email verification sign-in and disclose existing Pro gates; no fixed-code bypass or private credential was created. If certification requests dedicated access, supply an authorized supported method and verify it before resubmission.
