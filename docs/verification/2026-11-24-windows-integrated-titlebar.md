# Windows integrated title bar and desktop email entry

Approved scope: retain native Windows controls at the upper right, blend the title area into the existing split layout, and show email login immediately on Mac/Windows. Published Web keeps email hidden. No production deployment or TF trigger in this task.

Implementation: Windows hidden title bar plus native controls overlay; desktop-only drag regions and reserved control space; sync control symbols with appearance. Keep existing window lifecycle, tray and notification sync unchanged. Desktop email visibility follows the trusted desktop capability, independent of network discovery; server still validates sending and verification.

Checks: first render with unavailable capability endpoint for Mac/Windows and no desktop bridge for Web; system controls/drag/maximize/minimum size/light/dark/scaling; hidden-window sync and draft retention. Rebuild ARM64 and x64 Windows packages, run ARM64 in the existing VM, capture full native windows. x64 hardware testing remains outside available environment.

## Verified outcome

- Desktop email browser regression: Mac and Windows show the entry with capability requests blocked; ordinary Web hides it. No capability request is issued by either desktop.
- Actual Mac Electron runtime: email entry is visible immediately and opens the email address form.
- Final Windows ARM64 package on Windows 11 Pro ARM64 (200% OS scaling): light/dark, main window, settings, search, minimum 640×500 content size and 125% page zoom checked with full native-window screenshots.
- Native mouse actions: drag, double-click maximize/restore, minimize, maximize, restore and close-to-tray passed. Native snap layout was observed. Initial single-jump synthetic drag failed; stepped real mouse movement and HTCAPTION hit-test confirmed native dragging.
- Minimum-window control hit areas initially overlapped; corrected by retaining 36px system-control area plus 60px for the header, then reran successfully.
- Isolated server fixtures: authenticated notifications, remote edits/deletes/completions, hidden-window tray 2→7, no hidden record download, restoration retaining draft, count 7→5, Ctrl+R draft retention passed. This is actual Windows runtime testing with test data, not a new real-account email delivery or phone-to-production sync verification.
- Final ARM64 and x64 bundles: PE architecture and source/renderer bytes verified, ZIP CRC passed. x64 has not been executed on Intel/AMD hardware.
- Artifacts: `/Users/haer/Documents/Codex/2026-11-24/synca-windows-integrated`; Windows desktop `Synca Latest` targets the new isolated installation. Mac product source is updated, but no Mac installation/TF or production Web deployment was performed.

## Release authorization

After accepting the Windows package, the owner authorized submission and TF on 2026-11-24. Reuse the exact product-code verification above and merge through dev to main for automatic packaging. No production Web deployment is included; its email entry remains hidden.
