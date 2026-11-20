# Desktop Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the approved desktop presentation in shared Web/Electron without losing existing interactions.
**Architecture:** Preserve stateful components and existing contracts; add desktop-scoped styles, minimal navigation changes and unified synchronization entry points.
**Tech Stack:** React 19, TypeScript, existing Vite/Electron; no new dependency.
**Spec:** docs/superpowers/specs/2026-11-20-desktop-design.md

## Global Constraints
- Sidebar 200/236/360 and viewport bound preserved; no SidebarFrame behavior change.
- Existing search worker, excerpts, navigation, draft store, message writes retained.
- Desktop >=640px only visual redesign; no iOS/Windows build or production deployment.
- Existing working source captured at e169bd7; original working tree unchanged.

## Review Focus
- Shrinking window after saved360px, growing restores preference; keyboard and drag remain usable.
- Synchronizing with a draft, IME composition, category write, or active record edit must not reload or discard input.
- Search from a different category reveals a late match in a long record with no focus border.
- Settings child navigation respects feedback/category unsaved-change guards; close and back remain distinct.
- Low height, long labels, dark mode and keyboard-only use must not obscure or overlap actions.

### Task 1: Baseline and explicit behavior changes
Files: MessageSearch.tsx, MessageListView.tsx, desktop/frontend.patch, desktop/app/main.cjs; web/tests/desktop-design.browser.mjs.
- [x] Capture behavior and before images using real current source + fictional fixtures.
- [x] Add failing assertions for no search scopes/global matching, CmdR sync preserving draft/scroll, directly accessible settings.
- [x] Remove scope UI only; route refresh keys and native menu through existing refresh; prevent fetch during writes.
- [x] Verify search/time, draft, sidebar helpers and browser flows.

### Task 2: Desktop composition and settings
Files: DesktopDesign.css, main.tsx, FunctionMenu.tsx, SettingsPanel.tsx, ShellPanel.tsx, DeveloperSocialLink.tsx/CSS, locales.
- [x] Preserve existing message and input markup behavior; desktop tokens/spacing/footer controls/sidebar alignment.
- [x] Direct account + gear desktop entry; mobile path unchanged.
- [x] Settings account-first plan label, clear nested back/close; feedback social link.
- [x] Check light/dark, minimum window, widths and setting subpages screenshots and behavior guards.

### Task 3: Shared packaging and delivery
Files: desktop verification and docs/verification/2026-11-20-desktop-design.md.
- [x] Build Web and Electron shared renderer; run unit/browser and existing Electron regression on local fixture services.
- [x] Fresh final review of changes and high-risk behavior, fix material issues and rerun affected checks.
- [x] Install verified Mac build and update only Web preview; verify actual served assets and unchanged production homepage.

Review follow-up: preserved mobile scopes/feedback layout; separated manual sync from silent lifecycle refresh; strengthened secondary and selected-category count contrast. See verification record for scope and delivery evidence.
