# Synca cross-platform refinement implementation plan

Goal: implement user-approved account B, About B, icons, input polish and 10000-character text support. Preview only; no production, App Store Connect, PR merge or TF.
Architecture: preserve existing API and native/web components; extend text validation using grapheme counts on all platforms. No database migration. Feedback remains 2000 characters.

- [x] Backend: shared 10000 grapheme text validation for create/edit and AI paths; boundary tests ASCII/CJK/emoji; preserve request byte defenses.
- [x] Web: account B (small person + plan row, full-width single email row, quota), About B from approved demo, Synca Pro copy, broom clear-completed icon, colored category menu, six-line long-text expansion, 10000 editor/composer limits; test build/locales and behavior.
- [x] Native: same approved account/About, naming, shared outline action icons, small colored category menu dots, iOS unified rounded composer; investigate and repair iOS action hit testing with reproduction; 10000 grapheme limits and six-line expand/collapse with full copy.
- [ ] Root integration: inspect diffs, run meaningful API/client boundary tests, Mac+iOS builds, isolated actual-app and web screenshots. Exercise copy/completion/download, long text, editor cancel/save, dark/light, menu/color and account long email.
- [x] Preview deployment only after checks, preserve standalone demos, verify unchanged production fingerprint. Report each item with verification limits and screenshots.

Review risks: emoji counts must agree; request body limits may reject 10000 complex emoji; long text may block row controls; iOS drag gestures may capture taps; API failure must remain visible; full-copy must not copy collapsed preview; no current production credentials or records in QA.

## Verification results
- Backend build and 132 tests passed; Web build, 31 Vitest tests and 3 Node test files passed. Native test runner and 327-key localization validation passed. Final iOS Simulator and macOS QA builds succeeded.
- Actual iOS Simulator: copy followed by paste, completion count/state, image save success checkmark, bounded long composer verified. Physical iPhone remains a separate acceptance step. Initial All-list lazy-scroll behavior is not exhaustively verified.
- Actual preview: account B, About B, colored category menu and broom visible. Long-text full copy checked locally. Final native About visual and full light/dark/large-type matrix remain unverified.
- Preview release: 20261108T125828Z-b4fc505-preview (working-tree artifact). Production web SHA256 unchanged: 1c6f79143dfdefae912945425fe14a75adffbc764c1f4b31b1a6d91235d369f9. Three demo pages preserved.
- No PR/merge/TF or App Store Connect changes in this batch.
