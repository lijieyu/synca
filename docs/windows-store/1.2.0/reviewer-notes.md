# Reviewer notes — stable 1.2.0 (89)

Prepared for submission `1152921505702525382`. Not yet entered in Partner Center.

## Restricted capability: runFullTrust

Synca is an existing Electron desktop application packaged as MSIX. The runFullTrust capability is required to launch its Win32 Electron process and provide the existing desktop window, system tray, clipboard operations and user-initiated file dialogs. The application runs as the signed-in user and does not require administrator privileges. Microsoft Store manages this edition's installation and updates; it does not launch the website edition's updater.

## Release scope

This submission packages the released website version 1.2.0, build 89, for x64 and ARM64. It includes text and image records, Markdown, categories, task completion, search and account-based cross-device sync. General file uploads and MCP require the corresponding Pro entitlement. No 1.2.1 scratchpad, collection or screen-capture feature is included.

The Store edition uses a separate local profile to preserve the website edition's local data. On first launch, users sign in to their Synca account to access cloud content.

## Reviewer access — unresolved before certification

Verify the actual production sign-in flow and a supported reviewer account before submitting. Do not substitute the local CI synthetic account or invent a login bypass. Any private reviewer credentials belong only in the Partner Center certification notes, never in this repository or public evidence.

## Validation limits

Native Windows x64 and ARM64 CI checked the final unpacked package payload, version/build, separate profile, record creation and persistence after reload. Tests use an instrumented copy and a local backend. This is not evidence of Microsoft-signed MSIX installation, production sign-in or Store update delivery; those checks remain required.
