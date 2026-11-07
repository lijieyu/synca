# Synca visual upgrade implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development for implementation and independent review. User approved the v2 design and implementation; no further design approval is required.

**Goal:** Deliver the approved calm inbox on iOS, macOS and Web, retaining existing capabilities and complete Simplified Chinese, Traditional Chinese and English UI.

**Architecture:** Keep existing authenticated APIs, synchronization, attachment lifecycle and purchase behavior. Replace presentation/navigation; add device-local language/appearance preferences and platform-aware downloads. Never reset the root view to change language, since drafts and sheets must survive.

**Tech Stack:** SwiftUI/AppKit/UIKit; React/TypeScript/i18next.

**Spec:** `design-previews/Synca-A-三端交互稿-v2.html`, with the user's subsequent correction: expose Add Category at the end of the category list on every platform.

## Global constraints
- Desktop category sidebar; single stream only; remove parallel-column UI.
- Desktop bottom-left account/plan/visible daily quota is the only global management menu trigger.
- Menu: clickable Account & plan header; Settings, Categories, Connect AI; separator; Feedback, About, Log out. No separator before logout.
- iPhone exposes daily quota, sync, clear completed, more; category add remains visible after categories.
- Settings: language (system, zh-Hans, zh-Hant, en), appearance (system/light/dark), desktop download location. Browser capabilities must be handled honestly.
- Category editing, ordering, colors, default category protection, transfers and deletion semantics retained.
- Preserve text-only editing, conflict drafts, attachment preview/copy/download/expiry, upload retries, account deletion on native, purchases/restores/redemption, quota and storage errors, AI OAuth, feedback images, official links, sync behavior and accessibility.
- Product changes only; do not stage generated build outputs, data, feedback uploads, prototype artifacts or unrelated files. No deployment/TF in this task.

## Review focus
- Changing locale/appearance with an unsaved editor or composer never loses draft or authentication state.
- Long category/account names, CJK text and narrow windows never clip actions; add category is discoverable.
- Free quota reflects server access state; purchased users have no daily quota progress.
- Web unsupported/denied directory access falls back to normal downloads without losing attachments.
- Localization key parity, placeholders and persisted server/user data remain correct in all locales.

## Tasks
1. Web presentation and preferences (`web/src/components`, `web/src/index.css`, `web/src/i18n.ts`, locales). Add category visible, global account menu, quotas, native-like settings, complete locale resources, real download integration/fallback. Validate `npm run build`, focused behavioral checks, responsive screenshots.
2. Native presentation (`ios/Synca/Shared/Views`, `macOS/MacWindowBehavior.swift`) and preferences (`SettingsManager`, App root). Maintain existing closures/state, implement single-stream sidebar and account menu, iOS quota/add/clear, settings. Validate both Production targets and editor layout tests.
3. Localization integration: all native string lookups including Foundation errors/menus, complete zh-Hant resources/InfoPlist and Web AI instruction/access/error content. Validate key and format parity; review untranslated literals; avoid root identity resets.
4. Cross-platform regression and independent review. Build/test changed components; inspect rendered UI with representative signed-out/demo fixtures, dark/light and small screen; fix findings. Report verification limits honestly.

## Execution record
- Source paths were clean at start on dev; existing unrelated derived-data and user artifacts retained. Work in the established checkout with strict file ownership.
- User explicitly authorized implementation; the approved prototype and corrections are the design authority.
