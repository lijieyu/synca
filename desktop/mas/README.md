# macOS Electron TestFlight

Use the separate `desktop/SyncaElectronTF.xcodeproj`, shared scheme `SyncaElectronTF`, and the existing manual Mac-only Cloud workflow. Archive for `INTERNAL_ONLY`; do not modify or trigger the native iOS project. Official universal Electron MAS runtimes are checksum-verified, then signed through Apple-managed distribution.

## Production desktop release

On 2026-11-23 the owner explicitly authorized a production-connected Mac TF with email login and in-app Apple/email binding. This supersedes the earlier isolated-only restriction.

The default Cloud mode is now `production`: `build-mas-preflight.mjs --verified-production` requires `mas/production-release.json`, retaining the exact backend commit and artifact hash of its verified compatibility baseline. Migration, safe rollback and actual delivered-code login/sync evidence remain required. The current production policy also requires `webEmailEnabled: true`; the retired `webEmailHidden: true` assertion is rejected. An offline archive alone is insufficient.

`mas-production` uses `https://synca.haerth.cn` with an independent `Synca Electron Production` profile. It does not copy preview credentials or tokens. Users sign into their real account afresh; email-only identities never silently merge with Apple identities. Binding stays inside settings.

On 2026-11-25 the owner authorized public Web email login. The production release and anonymous-browser check in `docs/verification/2026-11-25-launch-web-release.md` confirmed headerless `/auth/capabilities` returns `email:true` and the public entry opens the email form. This supersedes the earlier Web-hidden policy; it did not repeat real email delivery. `backendCommit`, `backendReleaseSha256`, `backendRelease` and their original verification evidence remain the historical migration/rollback and login-compatibility baseline, not a claim about the newest deployed backend. `webEmailVerificationEvidence` records the separate current Web-availability check; do not invent a newer artifact hash or silently relabel old login evidence.

Production Web assets are not deployed by this workflow. Public browser capability discovery is expected to return email=true. Desktop preload still explicitly opts in, so email login is visible on first render without waiting for capability discovery; this is presentation metadata, not an authentication boundary. Server-side identity proofs and rate limits apply independently. The production MAS build uses an authenticated change stream in the main process, including while its window is hidden. APNs is enabled for production MAS with the macOS push entitlement; isolated builds still disable registration. Distribution signing/profile compatibility and actual APNs delivery must be checked on the next signed build. The stream and five-minute state check keep sync functional if APNs registration is unavailable.

## Retained isolated and offline modes

Set `SYNCA_TF_MODE=isolated` only for an intentional isolated release. It uses `mas/testflight-release.json` and `--verified-testflight`, connecting to the protected HTTPS preview host with its existing independent profile. The network-blocked credential window passes Basic credentials only to the exact unlock endpoint, rejects redirects and verifies the host-only Secure/HttpOnly cookie plus health. Renderer scripts cannot read the gate cookie.

The historical isolated proof records real email delivery and synthetic-code redemption/sync; it does not substitute for actual delivered-code production verification.

Without either verified flag, `build-mas-preflight.mjs` produces a strictly offline structural artifact. Never submit or launch it in place of an existing user installation.

## Export compliance declaration

The owner confirmed no France distribution and authorized persisting the reviewed declaration on 2026-11-24. For Mac 1.2.0 (87), App Store Connect was answered truthfully: standard encryption outside Apple's OS (Electron/Chromium/BoringSSL), and no distribution in France. Apple recorded `usesNonExemptEncryption=false`. This means exemption from documentation in the reviewed scope, not absence of encryption.

`build-mas-preflight.mjs` writes boolean `ITSAppUsesNonExemptEncryption=false` into the packaged root Info.plist. The wrapper copies it; `archive-stage.sh` checks both the source app and the final Xcode-processed root plist. Missing values, strings, true, or an unreviewed export compliance code fail the archive. Cloud runs the validator's regression tests before packaging. No declaration code or French filing is fabricated.

Reassess this conclusion before changing encryption functionality, adding custom/end-to-end/application-level stored-data encryption, changing runtime cryptography, or distributing in France. This configuration does not itself change App Store territories or TestFlight audiences. Existing uploaded binaries still need their build-specific metadata completed; it cannot retroactively modify them.
