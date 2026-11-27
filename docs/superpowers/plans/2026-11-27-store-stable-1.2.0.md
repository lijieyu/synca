# Stable 1.2.0 Microsoft Store launch Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. Preserve the existing dev branch.

**Goal:** Submit the website's released Synca 1.2.0 (89) to Microsoft Store, then switch the website's primary Windows link only after public availability and installation verification.
**Architecture:** Download the checksum-pinned published ZIP per architecture; preserve the released executable, renderer and application modules. Add only a Store startup adapter to isolate its profile, and MSIX metadata/assets. Reuse the existing manifest generator and Windows packaging library; do not rebuild from the 1.2.1 working tree.
**Tech Stack:** Electron released binaries, Node, electron-windows-msix, Windows SDK, native GitHub Windows runners.
**Spec:** User request in this chat on 2026-11-27: publish mature website-equivalent 1.2.0 first; publisher chosen Jieyu Li; replace website link only after success.

## Global Constraints
- Same dev branch, no extra product version, no 1.2.1 UI/features in the Store first release.
- Source build exactly version 1.2.0 / build 89 and published x64/ARM64 SHA-256 values from scripts/deploy-windows-downloads.sh.
- Package version 1.2.0.0, real identity must come from Partner Center; CI identity is not submittable.
- Preserve portable download and website local data. No purchased certificate; no production deployment before Store verification.
- User personally handles Microsoft login/identity/legal declarations; technical operations remain with the agent.

## Review Focus
- Wrong archive or architecture: reject before extraction.
- Accidental current renderer: preserve original ASAR files and verify all original content except package main metadata.
- Concurrent website/Store profile: Store adapter sets userData and sessionData before original startup.
- 1.2.1 claims in 1.2.0 listing: separate versioned materials and screenshots.
- Premature website switch: keep existing download until approved Store URL installs and works.

### Task 1: Fixed-source packaging
Files: desktop/store/stable-1.2.0.mjs, desktop/stable-store.test.cjs, desktop/build-stable-store.mjs.
- [x] Write tests for wrong hash, metadata, unexpected archive entries, original-file preservation and isolated startup. Run RED.
- [x] Implement source constants/validation, minimal startup adapter, content-preserving ASAR transformation and Windows-only MSIX packaging using existing storeManifest.
- [x] Run desktop tests GREEN and check actual released x64 archive locally; commit.

### Task 2: Native Windows evidence and version-correct materials
Files: .github/workflows/windows-store-stable.yml, desktop/stable-store-acceptance.mjs, docs/windows-store/1.2.0/*, docs/windows-distribution-maintenance.md.
- [x] Native x64/ARM64 jobs build exact stable source; fixture runtime verifies version 1.2.0/89, separate profile, no 1.2.1 navigation/update bridge and captures real Windows screenshots.
- [x] Prepare accurate 1.2.0 Chinese/English listings and submission notes. Keep production website unchanged.
- [x] Run native builds/tests, inspect artifacts and screenshots, fix actual failures and commit. Fresh review passed; final run 46001240270 succeeded on x64 and ARM64.

### Task 3: Formal Store submission and website change
- [x] Obtain authenticated Partner Center access; reserve approved localized names under Synca Notes and read assigned identity.
- [ ] Build with real identity, verify package installation, submit version-correct screenshots/listing and reviewer access. Personal legal steps go to user.
- [ ] Record submission/certification/public URL; verify actual Store installation. Only then update website primary link while retaining ZIP.
