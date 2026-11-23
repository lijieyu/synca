# macOS Electron TestFlight

Use the separate `desktop/SyncaElectronTF.xcodeproj`, shared scheme `SyncaElectronTF`, and the existing manual Mac-only Cloud workflow. Archive for `INTERNAL_ONLY`; do not modify or trigger the native iOS project. Official universal Electron MAS runtimes are checksum-verified, then signed through Apple-managed distribution.

## Production desktop release

On 2026-11-23 the owner explicitly authorized a production-connected Mac TF with email login and in-app Apple/email binding. This supersedes the earlier isolated-only restriction.

The default Cloud mode is now `production`: `build-mas-preflight.mjs --verified-production` requires `mas/production-release.json`, pinning the exact production backend commit and artifact hash. Migration, safe rollback, actual delivered-code login/sync and Web email-hidden checks must have passed before those assertions are recorded. An offline archive alone is insufficient.

`mas-production` uses `https://synca.haerth.cn` with an independent `Synca Electron Production` profile. It does not copy preview credentials or tokens. Users sign into their real account afresh; email-only identities never silently merge with Apple identities. Binding stays inside settings.

Production Web assets are not deployed by this workflow. Browser capability discovery returns email=false. Desktop preload explicitly opts in and requests capability discovery with `X-Synca-Client: desktop`; this is presentation metadata, not an authentication boundary. Server-side identity proofs and rate limits apply independently. The MAS build retains the existing sandbox/background polling behavior; native APNs is not enabled by this release.

## Retained isolated and offline modes

Set `SYNCA_TF_MODE=isolated` only for an intentional isolated release. It uses `mas/testflight-release.json` and `--verified-testflight`, connecting to the protected HTTPS preview host with its existing independent profile. The network-blocked credential window passes Basic credentials only to the exact unlock endpoint, rejects redirects and verifies the host-only Secure/HttpOnly cookie plus health. Renderer scripts cannot read the gate cookie.

The historical isolated proof records real email delivery and synthetic-code redemption/sync; it does not substitute for actual delivered-code production verification.

Without either verified flag, `build-mas-preflight.mjs` produces a strictly offline structural artifact. Never submit or launch it in place of an existing user installation.
