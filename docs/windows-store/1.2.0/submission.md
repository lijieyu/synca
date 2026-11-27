# Stable Store submission — 1.2.0 (89)

User changed the first Store release to the mature website version on 2026-11-27. Publisher display name selected: Jieyu Li. Registration was completed on the user's MacBook; authenticated access from the controllable Mac mini has not yet been established.

## Source and packaging
- Immutable website release: `1.2.0-20261125-r3`, both SHA-256 values pinned in `desktop/store/stable-1.2.0.mjs` and matching the original website publication script.
- Original executable, renderer, original main and all modules remain unchanged. ASAR package main points to a minimal Store adapter; the adapter isolates userData/sessionData at `Synca Store`, compatible with the later 1.2.1 Store profile. The full allowed delta is recorded in build-evidence.json.
- No website auto-updater exists in 1.2.0. Microsoft Store owns updates. No 1.2.1 feature code is imported or rebuilt.
- Package version 1.2.0.0. `runFullTrust` supports the existing Electron desktop runtime, tray, clipboard and user-selected file dialogs; no new screenshot permission/feature.

## Build and evidence
Workflow `.github/workflows/windows-store-stable.yml` runs native x64/ARM64 packaging and stable UI/profile checks without building current Web/UI code. Default is explicit CI identity. Real identity JSON is held in repository variable `SYNCA_STORE_IDENTITY_JSON`; set `SYNCA_STABLE_STORE_FORMAL=true` only after assigning the verified Partner Center identity, then a scoped dev push builds formal-identity packages. This avoids depending on a new workflow already existing on main. Alternatively use manual formal_identity once dispatch is available. No build submits or publishes automatically.

The Windows fixture uses instrumented copies, synthetic accounts and a local backend. Source preservation is checked on the uninstrumented package. Formal Microsoft-signed installation, production login and Store update behavior require separate evidence.

## Remaining release gates
- Reserve Synca; obtain exact Name, Publisher CN, PublisherDisplayName, DisplayName and Product ID from Partner Center.
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
