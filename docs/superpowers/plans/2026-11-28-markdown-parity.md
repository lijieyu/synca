# Markdown parity implementation plan

> Execution: superpowers:executing-plans, with independent Web and native work delegated under superpowers:dispatching-parallel-agents. User has explicitly authorized implementation and local commits; reuse dev and do not open a new branch or publish.

**Goal:** Records and scratchpad previews interpret the same supported Markdown on Web, Windows, iOS/iPadOS and native macOS, with one shared parser and fixture corpus.

**Architecture:** Reuse the existing remark/CommonMark + GFM ecosystem to produce a small, serializable AST. Bundle the same pure parser for JavaScriptCore on native platforms; render with native selectable text and SwiftUI block layouts, not one browser per feed row. Web records and scratchpad share one React renderer. Store/edit/copy retain source.

**Spec / decisions:** This document records the user's confirmed scope. Support ATX and Setext headings, nested lists/quotes, emphasis/strong/delete/explicit paired inline underline, inline/fenced/indented code, thematic breaks, tables/alignment, safe links/autolinks, and interactive task lists. Images never fetch arbitrary remote URLs; owned `synca-image:UUID` nodes resolve only through authenticated current-account assets supplied by the host. Unresolved images retain source/accessible fallback. Raw HTML is inert except exact paired inline `<u>` (no attributes); code is literal. Existing upload/storage/conflict behavior remains unchanged.

**Alternatives:** Continue independent regex parsers (rejected: recurring drift and incomplete nesting); embed WKWebView per record (rejected: feed cost and native selection/scroll regressions); shared parser with platform-native rendering (chosen by implementer: shared semantics, native controls, bounded cache). No new server schema or deployment.

## Shared interface

Parser source: `web/src/markdown/parse.ts`. Export `parseMarkdown(source: string): MarkdownDocument`, `toggleMarkdownTask(source: string, offset: number): string | null`.

Document: `{ version: 1, type: 'root', plain: boolean, children: MarkdownNode[] }`.
Node: `{ type: string, children?: MarkdownNode[], value?: string, depth?: number, ordered?: boolean, start?: number, checked?: boolean, taskOffset?: number, align?: ('left'|'right'|'center'|null)[], url?: string, title?: string, alt?: string, lang?: string, source?: string, position?: {start:{offset:number},end:{offset:number}} }`.
Standard mdast types; normalize reference links/images; exact paired underline becomes `underline`; unsafe links become inert text/children; preserve original image source. Only parsed task-list items get `taskOffset`, in UTF-16 source units. Node types: paragraph, text, heading, strong, emphasis, delete, underline, inlineCode, code, break, blockquote, list, listItem, thematicBreak, table, tableRow, tableCell, link, image, html (literal).

Native resource: `ios/Synca/Resources/markdown-parser.js`, deterministic IIFE exposing `SyncaMarkdown.parseJSON(source): string` and `SyncaMarkdown.toggleTask(source, offset): string|null`. Native evaluates only this bundled resource in JavaScriptCore; user text is a function argument, never executable script. A bounded parsed-document cache avoids reparsing during layout. Parser failure preserves raw text.

Shared corpus: `tests/fixtures/markdown-parity.json`, array `{id, source, contains: string[], types: string[], taskCount: number, plain?: boolean}`. Assertions cover meaningful semantics, not parser implementation. Native and Web consume the exact same file and test UTF-16 task edits and literal/security boundaries.

## Global constraints / review focus

- Preserve iOS 16 / macOS 13 floors, existing app structure, local-only release scope, original source and account ownership.
- No markdown-triggered remote image fetch or HTML/script execution; link protocols limited to http/https/mailto/tel.
- Tasks modify only the parsed bracket's middle character; preserve CRLF, emoji, concurrent text and existing conflict checks. Disabled/busy semantics and accessible labels.
- Tables/code scroll horizontally within content width; record fold and vertical feed scroll remain usable. No heavy WebView per row.
- Dynamic Type, light/dark, links/text selection, plain whitespace, long and malformed input and image-in-code all receive tests. Maximum accessibility layout limitations must be fixed or accurately reported, never relabeled a pass.

## Task 1 — Shared parser and Web/scratch renderer
- [x] Add failing shared-corpus/security/task-offset tests, then implement parser and reproducible native bundle build/check.
- [x] Replace divergent Web record/scratch Markdown paths with the common renderer; retain protected images and persistence, support task toggles in scratch preview.
- [x] Run full Web Vitest plus Node tests separately, TypeScript/build and browser interaction checks.

## Task 2 — Native shared document renderer and integration
- [x] Consume bundled parser through JavaScriptCore; test the shared corpus and task edits before implementation.
- [x] Replace native record and scratch block parsers with one renderer. Selectable styled text, tables, code, nested structures, native task controls, safe image resolution. Retain fold/search/editor/copy behavior.
- [x] Integrate task writes with current conflict/account boundaries, errors and accessibility.
- [x] Run native regression tests and iOS/Mac builds; isolated iPhone/iPad/Mac fixtures and screenshots, one simulator at a time.

## Task 3 — Cross-platform acceptance and commit
- [x] Inspect the same fixture in record and scratch modes across native/Web/Electron; use actual Windows when available and distinguish any coverage gap.
- [x] Review source/data safety, source-preserving task edits, parse parity, selection/folding and rendering. Fix material issues and rerun affected tests.
- [x] Archive screenshot index and logs, update 1.2.1 requirements/acceptance; local commit(s), no push/deploy.
