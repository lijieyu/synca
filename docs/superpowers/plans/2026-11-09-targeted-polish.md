# Targeted Synca polish implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement task-by-task.

**Goal:** Address only the user-reported issues and approved demo interactions, preserving previously accepted product layouts.
**Architecture:** Incremental patches to existing SwiftUI/AppKit and React components. Existing API color tokens remain backward compatible; optional palette hex metadata adds the expanded palette. No wholesale demo-to-product replacement.
**Tech Stack:** SwiftUI/AppKit/UIKit, React/TypeScript, Express/Kysely/SQLite.
**Spec:** docs/superpowers/specs/2026-11-09-targeted-polish.md

## Global Constraints
- Work only in /tmp/synca-pro-preview, baseline c807f79. Preserve unrelated untracked files. No automatic commits/push/merge, no production deployment or ASC changes.
- User authorized implementation and preview update. Demo is reference for requested behavior only, not a replacement app.
- Keep English/Simplified/Traditional Chinese complete. Preserve existing functionality and safe session behavior.
- Native prices from StoreKit displayPrice; no hardcoded native purchase price. Web price ¥28 only.
- Keep legacy color tokens sky,mint,amber,coral,violet,slate,rose,ocean unchanged. Optional colorHex/categoryColorHex fields must not break older clients. No unknown color tokens on legacy wire fields.
- Default category may change color, never delete or reorder. Rename protection remains as existing.

## Review Focus
- Default category and stale client changes must not lose palette metadata or allow protected deletion.
- Reorder failure/cancellation must restore order, maintain selection/focus, and not cross users.
- Native Chinese composition/caret visibility must survive scrollbar fix.
- AI OAuth/embedded session cannot leak tokens to external sites; revoke requires deliberate confirmation.
- Paid/free/price-loading states must remain distinct, no invented native price.

### Task 1: Compatible palette API and default-category color
Files: backend/src/{app,store,types,db,migrate,aiCore}.ts (discover exact migration organization), backend/tests/api.test.ts and appropriate tests.
- [ ] Add additive nullable color_hex storage and optional wire colorHex for categories, categoryColorHex for records with category metadata; old rows and old clients work. Preserve metadata for name-only writes; legacy color changes intentionally clear override.
- [ ] Support exactly 16 named presets: existing 8 canonical tokens/colors plus 8 additional hex values (#676d78,#4169a8,#4a9a9d,#8da35e,#d9b24b,#df8e73,#af597b,#8276c2), mapped to nearest legacy token. Expose shared backend constants; clients mirror explicit palette values. Validate colorHex against allowed presets; no arbitrary input.
- [ ] Permit default-category color-only patches; reject rename/delete/order. Keep mutation timestamps and record metadata consistent. Check AI category writes preserve/clear metadata coherently.
- [ ] Write regression tests: create/read/update metadata, default color vs rename/delete, old payload compatibility, invalid hex, isolation, sorting. Run backend suite/build. Document exact contract for Tasks 2/3.

### Task 2: Native targeted changes
Files: ios/Synca/Shared/Views/{MessageListView,MessageBubbleView,MacSelectableText,MacInputTextView,AccountSheet,AccessCenterView,AppSettingsView,AIConnectionView}.swift; native models/API/sync and locale files as required.
- [ ] Implement all native IDs in spec: brush visible size match refresh; iOS floating composer no outer line/background; remove infinity; neutral high-contrast All; category dots in item/menu; Mac sidebar reorder; account menu width equals card; identity first line email, second plan.
- [ ] Category manager direct inline name, explicit delete + confirm, 16 preset compact picker (4x4, 44pt targets, selection check), default editable color, drag reorder and accessibility actions; iOS full screen; remove explanatory text. Use Task1 colorHex contract without changing legacy enum tokens.
- [ ] Account uses existing layout with localized single Synca Pro heading + gray activated status when owned; no duplicate plan near identity, no checkbox/date/price/purchase CTA for paid; attachment storage at top all platforms, remove separator; iOS medium/large sheet; preserve native restore/legal requirements where applicable. Native purchase displayPrice from StoreKit, error/retry on fetch failure, not ¥28 constant.
- [ ] Mac settings fit contents, menu same width. Investigate and fix input overflow scroller without IME regression. Reproduce long-text layout discrepancy, unify measured/displayed typography; preserve selection/links; center expand/collapse iOS/Mac; no excessive gap before collapse.
- [ ] AI native first loading centered (no corner spinner), preserve failure/retry and trusted session bootstrap; diagnose embedded marker issue without unsafe session changes. Measure loading where feasible.
- [ ] Complete 3 languages; run native focused tests/localization/Mac+iOS simulator builds. Capture real app screenshots using isolated QA fixture (no production writes); state gaps. Record tests for failures and source of fix.

### Task 3: Web targeted changes and AI interactions
Files: web/src/components/{MessageListView,CategoryManager,PlanDialog,FunctionMenu,AIPage,BroomIcon}.*; web/src/{calm.css,api/client.ts,locales/*}; relevant tests.
- [ ] Implement web IDs: slightly larger visible brush; same-width menu/card; sidebar drag reorder + keyboard alternative, rollback on failure; All neutral high contrast. Category manager direct edit/delete/sort, no helper copy, compact 16-color picker/default color via Task1 contract. Preserve existing add/edit dialog layouts outside scope.
- [ ] Account remove agreements, align typography with existing dialogs; storage at top, no separator; paid single Synca Pro + gray activated status, no duplicate plan/checkbox/date/price. Free retains upgrade with ¥28 one-time purchase and App Store link. Don't overhaul unaffected modal layout.
- [ ] AI: mobile/embedded no web header/footer; first-time existing tutorial preserved; linked app heading right text link '查看连接教程'; recent operations initial3, plain centered chevron expand/collapse, existing server limit communicated only as needed; revoke confirmation, cancellation no mutation, pending disabled/error recoverable.
- [ ] Center first loading, don't replace existing content during refresh; inspect resource/API timing and reduce avoidable load without changing authorization contract. Native bootstrap marker must remain compatible. No fake successful connection.
- [ ] Complete 3 languages. Run Web tests/build, backend compatibility check; inspect browser mobile/desktop light/dark and revoke/cancel/no-connection/states with isolated fixture.

### Task 4: Integrated acceptance and preview only
- [ ] Independent scoped reviews after tasks, resolve reported issues, whole branch review.
- [ ] Audit all spec IDs with evidence (source/test/screenshot) vs gaps, including repeated long text toggle and resize, input IME, palette default + legacy compatibility, reorder failure.
- [ ] Build production configuration native apps and Web; run suites once after final relevant edits.
- [ ] Deploy only isolated preview with scripts/deploy-preview.sh; verify asset checksums/health and unchanged production root/AI artifact.
- [ ] Report exact completed IDs and any verification limitation, provide screenshots and preview URL. No TF or PR unless later authorized.

## 最新用户纠正（优先于前文，2026-11-09）
- iOS/Mac/Web 主界面 Synca 名称后都不显示 Pro 紫色标签，不新增、不保留。
- 账号与套餐中，邮箱地址下面统一显示当前套餐（免费版 / Synca Pro），不显示“通过 Apple 登录”。
- 下方照常保留权益卡片，已购展示权益；未购保留升级引导。此处允许账号身份区与权益卡标题各出现一次套餐名，去掉额外徽标，不再执行“账号区去掉套餐”的旧方案。
