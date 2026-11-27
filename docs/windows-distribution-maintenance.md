# Windows distribution maintenance — Synca
Owner: Synca developer. Same version and dev branch as other 1.2.1 work. Never deploy from a failing verification run.

## Two channels
| Item | Website | Microsoft Store |
|---|---|---|
| Artifact | portable ZIP + Squirrel Setup.exe | MSIX (x64/ARM64) |
| Update owner | Electron autoUpdater/Squirrel | Microsoft Store |
| Profile | `%APPDATA%/Synca Electron` (same as released 1.2.0) | Store-specific `Synca Store` within Windows package storage context |
| Integrity | fixed HTTPS origin + strict artifact path/size/SHA-256, then verified loopback full-package feed | MSIX integrity plus Microsoft signature upon publication |
| First installation trust | unsigned website binaries may show SmartScreen | Microsoft-signed Store distribution |
| Certificate cost | none purchased; do not promise warning-free unsigned website installs | no third-party signing certificate required for Store submission |

Profile contents are never moved or deleted by the update logic. Do not rename productName, NuGet identity `Synca`, executable `Synca Electron.exe`, website profile or Store identity in routine releases. Different channels have separate local state; sign into the same account to sync cloud content. Do not copy a running Chromium profile.

## Reproducible build and validation
Use `.github/workflows/windows-distribution.yml` on current `dev` (`gh workflow run windows-distribution.yml --ref dev` once registered on default branch, or push a scoped change). This workflow only builds/tests and uploads 14-day artifacts; it cannot deploy production. `gh run view RUN_ID --log-failed` for diagnostics; download the accepted run’s artifacts before expiration and retain them with checksums and commit SHA.

Local Mac tasks remain the normal Web/iOS/Mac build. Windows-specific commands run on the Windows Runner with Node 24, Windows SDK and Visual Studio C++ tools, locked npm dependencies. The Windows window enumerator is compiled for the target architecture and packaged in `resources/native`; screenshot startup does not invoke PowerShell or compile code at runtime:

```powershell
$env:SYNCA_WINDOWS_ARCH = 'x64' # repeat for arm64
npm ci --prefix ../web
npm ci
npm run build:windows
node build-windows-installer.mjs x64
node build.mjs win32 store
# CI-only package, explicitly not for submission:
node build-windows-msix.mjs x64 --ci
# Actual submission identity JSON from Partner Center, outside git:
$env:SYNCA_STORE_IDENTITY = 'C:/secure/synca-store-identity.json'
node build-windows-msix.mjs x64
```
Identity JSON keys: `name`, `publisher`, `publisherDisplayName`, `displayName`. All values must match Partner Center. Never substitute test identity in a release. `WINDOWS_KIT_PATH` can point to the installed SDK's x64 tooling directory. MSIX uses marketing version `major.minor.patch.0`; fourth component stays 0. A rejected package that requires a new version must use a genuinely higher approved package version, not overwrite previously released bytes.

After obtaining the assigned identity, configure repository variable `SYNCA_STORE_IDENTITY_JSON` with these four public package-identity fields (never login credentials). Manually dispatch the same workflow with `store_submission=true` to build the formal-identity MSIX; missing identity fails closed. Default push builds remain CI-identity packages. The workflow does not submit or publish either variant. Failed runs retain compact diagnostic evidence; distributable packages upload only after the verification steps succeed.

## Website publication gate and order
1. Pass Windows tests, actual legacy 1.2.0 (89) migration, native Setup/Squirrel update/restart/failure tests, screenshot functionality and a production-sign-in smoke check using an authorized test account. Verify both supported architectures on Windows hardware/compatible VMs; each architecture now has its own native Windows Runner; inspect both results.
2. Verify the matching 1.2.1 backend contracts are deployed and healthy before making a new client available. Keep iOS/macOS versions in `/app-updates` tied to actual Store availability. Do not auto-advance them with Windows.
3. Archive the accepted ZIP, Setup, full nupkg, RELEASES, release.json, build/evidence log and SHA-256 under a version+commit directory. The current 1.2.0 immutable URLs remain valid.
4. Stage Setup/nupkg at their exact `release.json` URLs: `https://synca.haerth.cn/downloads/windows/{arch}/Synca-{version}-{arch}-Setup.exe` and `Synca-{version}-full.nupkg`. Never replace bytes for an existing version. Serve no directory listing. HTTPS must validate normally; do not weaken TLS to work around a deployment error.
5. Verify public GET byte count and SHA-256 against the accepted artifacts. Then atomically replace the server's APP_RELEASES_PATH JSON after schema validation. No catalog entry until all referenced bytes are reachable and verified. RELEASES is mutable/no-cache; versioned files immutable. New installed clients require `package:{name,bytes,sha256,sha1}`; legacy manifests remain backend-compatible.
6. Switch homepage primary Windows link to Setup and retain an explicit portable ZIP link plus checksums. Existing 1.2.0 homepage links remain until gates pass. First upgrade from 1.2.0 is manual: close the old portable app, run the official new Setup, then open Synca. 1.2.0 cannot acquire an updater retroactively. Subsequent installed versions use download → ready → restart/install.
7. If catalog/artifacts fail validation, hide the release entry, keep old clients/data available, fix and retest a new immutable version. Do not downgrade a live installed Squirrel version or overwrite an existing package. Setup failure keeps the running app open; preserve logs and offer retry.

## Store release and ongoing updates
- Complete personal login/identity/legal steps through the official onboarding portal. Verify eligibility, reserve the actual app name, record assigned package identity and Product ID (not credentials).
- Use `docs/windows-store/` listing and review materials. Obtain actual Windows screenshots, ≥1366×768 PNG, <50 MB each. Upload per locale; do not use website auto-update screenshots in a Store listing.
- Build with the assigned identity; MakeAppx validation is part of packaging. Run Windows App Certification Kit and Store-installed smoke tests on a compatible Windows desktop before claiming certification readiness. A CI package and a cross-build are insufficient.
- Verify public privacy/support URLs, exact commerce declarations, real reviewer access and IARC answers. User handles legal acceptance and identity verification. Submit only after these gates pass; retain submission ID, certification result and live Store URL.
- Microsoft signs and distributes the approved MSIX and owns updates. Keep both native `process.windowsStore` and packaged marker guards. For every later release, test Store upgrade retaining local state separately from website upgrade.
- After publishing, verify the live install/version on Windows, account sync, basic record operations and Store update discovery. Record actual results, never treat upload success as publication.

## Evidence limits
`windows-acceptance.mjs` downloads the checksum-pinned real 1.2.0 archive, uses instrumented test copies of released/current binaries, and redirects traffic to a synthetic loopback service. It verifies auth cookies/tokens, localStorage, IndexedDB, preferences and local files; tests actual Windows renderer/capture. Squirrel test installs the real 1.2.1 Setup on a disposable runner, instruments that installed test instance, and upgrades to a synthetic 1.2.2 package. Synthetic 1.2.2 is never published or uploaded as a release. Store runtime marker checks are not Store-signed install/update proof.

References (checked 2026-11-27): [Electron updater](https://www.electronjs.org/docs/latest/api/auto-updater/), [distribution options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path), [MSIX requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-package-requirements?pivots=store-installer-msix), [account registration](https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/open-a-developer-account?tabs=individual), [Store screenshots](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images), [version numbering](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/package-version-numbering?pivots=store-installer-msix).

## First Store release revised to stable 1.2.0 (2026-11-27)
The user chose the website's mature 1.2.0 (89) for the initial Store submission. Use `desktop/build-stable-store.mjs`, `.github/workflows/windows-store-stable.yml`, and `docs/windows-store/1.2.0/`; do not use the current 1.2.1 renderer, screenshots or listing. Source ZIP hashes are fixed to the published release. A minimal Store startup adapter isolates local data while preserving released modules. Package identity remains the same across future Store upgrades, and the profile is `Synca Store` from the first version.

The user authorized replacing the website's Windows primary download link only after actual Store publication and installation verification. Retain both portable ZIP architecture links. This supersedes a Setup-first homepage plan for the initial Store launch; no link change before the live Store result is verified.
