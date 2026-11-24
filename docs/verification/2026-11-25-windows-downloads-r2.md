# Windows 1.2.0 (88) and latest website preparation

## Scope and current live state

Prepared for the authorized overnight release; publication is coordinated after the release merge. This task did not deploy, submit an App Store build, change distribution, or change Web email configuration.

Before publication, a read-only HTTPS fetch from the production host confirmed that `/downloads/windows/1.2.0-20261125/SHA256SUMS.txt` still matched the two previously published build 87 packages, `/auth/capabilities` returned `{"email":true}`, and the current homepage release was `/opt/synca/home-releases/20261124T172718Z-3e43246`. Local DNS resolution was intermittent, so this check used the known production SSH host and its HTTPS resolver.

## Prepared changes

- Desktop marketing version stays 1.2.0; the project build number is 88. The Xcode project has one `CURRENT_PROJECT_VERSION` occurrence. Xcode Cloud manages its eventual archive number independently.
- All three homepage locales, at both download entry points, display Windows 1.2.0 (88) and link to new immutable release directory `/downloads/windows/1.2.0-20261125-r2/`. Existing architecture guidance, portable/unsigned notice, Apple download destinations and Web links remain intact.
- `deploy-windows-downloads.sh` pins the new package hashes and verifies build 88. It retains its immutable directory and exact-public-byte verification behavior; old build 87 URLs are not overwritten.
- The existing homepage browser test now sets lazy images to eager before decoding. Jumping directly to the footer on narrow pages had skipped some images and left the test awaiting their decode indefinitely. This is test-only; production lazy loading is unchanged.

## Build provenance and package verification

Artifacts and source snapshot: `/Users/haer/Documents/Codex/2026-11-25/synca-windows-public-r2`.

- Base revision: `15ed2319fc7b01c1990c5b5a24e11ea828c8535e`, plus the recorded `source.patch` (not an unmodified commit build).
- Source patch SHA-256: `34936f34966ed9c91b03983eedff3e4b707f897c96eac23eaa8b5139d91d4506`.
- Source manifest SHA-256: `f443bc837f7db15a35c768fe462c331b25a03d6d57c070b2207c20c1a2ed8155`.
- `MessageSearch.css` SHA-256: `111dc8501b3a58da6eadf1edd2d310ca5ca52dccb8ff1afb305eed4240799cf0`, identical to the pending release source. Packaged CSS explicitly includes the corrected 20px header inset.
- Runtime: Electron 45.3.2; production origin `https://synca.haerth.cn`; both original runtime ZIP checksums validated before packaging.
- Both package ASAR files are identical: `b5349398b9a219d560c0a6b2e8fe91cee3a3b90f06fdc29f30222ed37d715d76`.
- All 190 packaged app/renderer files per architecture matched the build snapshot (380 comparisons). `package.json` has only the packager's expected removal of `private`. No preview marker is present.

| Architecture | File | SHA-256 |
| --- | --- | --- |
| ARM64 | `Synca-1.2.0-Windows-arm64.zip` | `33bbad92f518498d0801066149f0ade4269dc4594eddaa29770c323016e09017` |
| x64 | `Synca-1.2.0-Windows-x64.zip` | `d1ce67cb7ed7a004d8864efa9bd34811d07c99c1ff011e642d687e4b8294a402` |

The snapshot built successfully with TypeScript and Vite. ZIP CRC, full SHA-256, PE architecture, unsigned certificate-table state, and packaged 1.2.0 (88) metadata all passed. The publication script's `--check` passed with these exact ZIPs. Existing Windows compatibility/build identity/preview tests (10) and homepage SEO/routing tests (5) passed. The homepage browser suite passed all 12 locale/viewport/theme cases, keyboard entry, locale navigation, and tutorial interactions with zero page errors. Screenshots and JSON evidence are beside the artifacts; the 320px English dark screenshot was visually reviewed.

No fresh Windows VM execution was performed. Native `desktop/app` and `desktop/ui` sources are unchanged from verified Windows baseline `90fb3d7`; previous ARM64 native-window/tray/sync acceptance remains applicable. x64 still has no Intel/AMD hardware execution evidence. The new renderer's Windows-specific visual behavior is not claimed as real Windows acceptance.

## Coordinated publication order

Only after the release merge, publish verified ZIPs first, then publish the homepage links. Run nginx-changing deployments sequentially.

```sh
bash scripts/deploy-windows-downloads.sh --check /Users/haer/Documents/Codex/2026-11-25/synca-windows-public-r2
bash scripts/deploy-windows-downloads.sh /Users/haer/Documents/Codex/2026-11-25/synca-windows-public-r2
bash scripts/deploy-home.sh
```

The first publication command verifies full public HTTPS bytes, checksum response, unknown-file 404, and health. After homepage publication, verify all three live pages use `1.2.0-20261125-r2/` and display `Windows 1.2.0 (88)`; confirm `/auth/capabilities` still returns `email:true`. Do not claim the new files are public until this succeeds. Shared renderer Web deployment is handled by the coordinating release task.
