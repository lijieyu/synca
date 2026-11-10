# Basic Markdown display

Goal: Render basic Markdown consistently across records on Web, iOS and Mac while preserving plain-text composition, editing and original-source copying.
Architecture: Scoped record renderer on Web, attributed text in native existing selectable text surfaces. Clipboard conversion only where structured list data exists; no HTML execution or remote resources.
Tech stack: React/TypeScript, Swift/AppKit/UIKit.

- [x] Add renderer regression tests and compact safe rendering for lists, bold, quotes, inline code and links.
- [x] Preserve structured clipboard list markers without changing normal text or attachment paste.
- [x] Verify rendered overflow, expand/collapse and original-source copy.
- [x] Build Web and both native targets; inspect fixture screenshots, one simulator at a time.
- [x] Report local implementation and verification boundaries; no deployment requested.

Verification: Web 90 Vitest + 3 Node tests; isolated Chrome paste/copy/edit/folding checks (6 clipboard cases); native renderer, isolated clipboard, existing IME tests; iOS simulator last long-text collapse and Markdown collapse; both native builds. No deployment.

Boundary: Structured list paste is supported in composers; native editing retains existing plain-text components. HTML containing preformatted code falls back to original plain text to protect indentation. Unsupported rich-list representations fall back to supplied plain text.
