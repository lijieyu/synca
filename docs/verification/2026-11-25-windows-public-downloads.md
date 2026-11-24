# Windows public downloads preparation

The owner authorized a Windows download on the public website. The packages below were rebuilt from the current shared renderer, rather than publishing the older November 24 packages. This record describes prepared artifacts; public publication and HTTP verification are recorded by the coordinating release task.

## Exact artifacts

- Product: Synca 1.2.0 (87), Electron 45.3.2, production origin `https://synca.haerth.cn`.
- Portable unsigned ZIPs: extract the entire directory and run `Synca Electron.exe`.
- Local directory: `/Users/haer/Documents/Codex/2026-11-25/synca-windows-public`.
- Source base: `0f6de6beb803d77db068ebf98d29110a604ff41d` plus the current authorized Web email discovery changes and website snapshot. `source.patch`, `SOURCE-SHA256SUMS.txt`, `BUILD-PROVENANCE.json`, and `build.log` are retained alongside the local packages. The packages do not claim to be an unmodified build of the base revision.
- Source patch SHA-256: `cdcc81b163765cd6b3c71452e57d97b356121bbaf6a594c1ba4dcec6ff9aef6d`.
- Source manifest SHA-256: `1a3fb8dfeca28a423c595a798aeabf2388e64d272f8c71b7b85c5b97f92568e3`.

| Architecture | File | SHA-256 |
| --- | --- | --- |
| ARM64 | `Synca-1.2.0-Windows-arm64.zip` | `b162e19e3eefe8f59cc5813358f59f3dd1d352f9c26bd84f2de2c1ec7b3ea6a1` |
| x64 | `Synca-1.2.0-Windows-x64.zip` | `5a2f97965464385b55a8b2a92ef6f6363b8dbc3bbe79a65e5d29e4d01beda82d` |

Both packages contain the same `app.asar`, SHA-256 `e7e1191b5ef889382cede859f7b78cab4ec6fb463fdcb2742d82fbfa59454583`.

## Verification and limits

- Official Windows runtime archive checksums verified by `desktop/build.mjs` before packaging. Shared renderer TypeScript and Vite build passed; both architectures packaged successfully.
- All 189 application/renderer files in each ASAR match the build snapshot; packager's expected package.json normalization was checked as parsed JSON. Both ASARs are byte-identical and have no preview build marker.
- ZIP CRC, full ZIP SHA-256, PE machine type, unsigned PE32+ certificate table and packaged 1.2.0 (87) metadata pass for both architectures.
- Ten existing Windows compatibility, build identity and preview isolation tests pass.
- Native `desktop/app` and `desktop/ui` source is unchanged from verified Windows baseline `90fb3d7`. Reuse the November 24 ARM64 native-window/tray/sync acceptance in `2026-11-24-windows-integrated-titlebar.md`; these new packages were not run through another Windows VM session. x64 has no Intel/AMD hardware execution evidence. Current shared renderer includes the later settings/style/AI-brand changes; this preparation does not claim a fresh Windows visual acceptance of those changes.
- The independent publication script passes shell syntax, exact-artifact check, offline nginx route insertion/idempotence, refusal of an unexpected existing downloads route, and rejection of altered package bytes before any network write.

## Publication contract

The stable immutable directory is `https://synca.haerth.cn/downloads/windows/1.2.0-20261125/`, containing the two ZIP filenames above and `SHA256SUMS.txt`. These URLs are prepared targets until the publish command succeeds.

Run from the repository:

```sh
bash scripts/deploy-windows-downloads.sh --check /Users/haer/Documents/Codex/2026-11-25/synca-windows-public
bash scripts/deploy-windows-downloads.sh /Users/haer/Documents/Codex/2026-11-25/synca-windows-public
```

The script uploads into a non-public staging directory, verifies exact pinned package hashes, atomically installs an immutable version directory under `/opt/synca/downloads/windows/`, and adds only the dedicated nginx alias. It refuses different bytes at an existing version URL. It does not restart the backend, alter databases, modify the app/Web/home release pointers, or purchase/use signing credentials.

After `nginx -t` and reload, the script downloads each full public HTTPS ZIP and compares its SHA-256, verifies the checksum file, verifies unknown download paths return 404, and checks application health. Public paths use immutable caching and do not fall back to the app HTML. Coordinate nginx-changing deployments sequentially. On a publication error, the script restores its nginx backup; it retains verified package files and staging evidence.

To withdraw downloads later, first remove the website download links and remove only the dedicated downloads location before testing/reloading nginx. Keep immutable files for audit and do not reuse the same version URLs for different bytes. A historical whole-nginx backup must not overwrite homepage/API route changes made after this publication.
