# macOS Electron TestFlight preparation

Separate Xcode project `desktop/SyncaElectronTF.xcodeproj`, shared scheme `SyncaElectronTF`, macOS only. Never route the app to production or use any ordinary Mini preview package in TestFlight.

`build-mas-preflight.mjs` creates a strictly offline structural proof from the two release ZIPs validated against the Electron npm package's SHA-256 list. This artifact carries the existing app's bundle ID only for compatibility verification. It is **not** a beta to put in TestFlight, and must not be launched in place of an existing user install.

A production-suitable internal beta must pass proof for the exact real, isolated HTTPS email/sync backend and the real packaged Mac presentation. That build must use its own Electron data namespace, App Sandbox policy, and Apple-managed distribution signing; distribute using the standalone Mac-only archive action with `INTERNAL_ONLY`, with no automatically started runs or external groups. Do not modify the existing native Xcode project.

The shipped TestFlight mode consumes only the HTTPS preview host already configured
for Synca. The credential window has an in-memory, network-blocked scope. The
main process passes its user-entered Basic credentials only to that host's exact
unlock endpoint, never follows a redirect carrying them, and verifies a host-only
Secure/HttpOnly cookie and Synca health before letting the product renderer open.
Email sign-in follows normally through the independent session path; the renderer
cannot read the preview gate cookie. No production token/profile is migrated.

The verified-release config records the exact HTTPS origin, backend commit and
release hash, independently verified real delivery to the allowed test inbox,
and one-time-code, write and read-back coverage with a synthetic code. It
does not claim the actual delivered code was redeemed. The protected live
host and the exact packaged Mac scope must also be independently confirmed.
A successful offline archive alone cannot substitute for release evidence.
