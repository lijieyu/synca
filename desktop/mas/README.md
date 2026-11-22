# macOS Electron TestFlight preparation

Separate Xcode project `desktop/SyncaElectronTF.xcodeproj`, shared scheme `SyncaElectronTF`, macOS only. Never route the app to production or use any ordinary Mini preview package in TestFlight.

`build-mas-preflight.mjs` creates a strictly offline structural proof from the two release ZIPs validated against the Electron npm package's SHA-256 list. This artifact carries the existing app's bundle ID only for compatibility verification. It is **not** a beta to put in TestFlight, and must not be launched in place of an existing user install.

A production-suitable internal beta must pass proof for the exact real, isolated HTTPS email/sync backend and the real packaged Mac presentation. That build must use its own Electron data namespace, App Sandbox policy, and Apple-managed distribution signing; distribute using the standalone Mac-only archive action with `INTERNAL_ONLY`, with no automatically started runs or external groups. Do not modify the existing native Xcode project.
