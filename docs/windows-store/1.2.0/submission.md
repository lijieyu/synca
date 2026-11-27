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
