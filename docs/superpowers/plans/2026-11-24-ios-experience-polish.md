# iOS experience polish

Goal: carry the previously approved phone sidebar and unified native settings into the current release baseline, preserving sync, input, search and native Mac behavior.

The user authorized implementation on 2026-11-24. This is restoration and refinement of previously approved navigation rather than a new product design. Existing local drafts under /Users/haer/Projects/synca are references only; do not move/reset/stage them. Only reuse the phone-specific presentation sections, not their older sync lifecycle.

## Design decisions

- Phone: left category drawer; top-right search, sync and original broom remain separate. Use a leading-edge gesture to avoid hijacking horizontal markdown/table interaction. Category dots and subtle selected color identify categories; counts align at the trailing edge.
- Settings: native NavigationStack, account first without plan subtitle (latest accepted desktop direction), system grouped settings rows, neutral controls. All child destinations use the parent's navigation, with a visible native back button. iPad uses a large sheet; avoid a stretched full-screen phone list.
- Feedback: stable large sheet with cancel/send and draft discard confirmation; remove redundant image heading/count copy. Keep the developer contact link.
- Lifecycle: aggregated App scene state owns notification stream lifetime. Showing full-screen settings must not stop it. APNs synchronization failure must report failed and must not replace a push badge with stale local data.
- Keep native Mac presentation, rich text/search implementation and production services unchanged. APNs actual delivery requires a signed real device and cannot be inferred from simulator screenshots.

## Work and checks

- [x] Inspect released code, uncommitted historical design and available simulator inventory.
- [x] Capture real baseline screens with an isolated account fixture.
- [x] Restore phone sidebar and native settings, remove duplicate navigation and unstable sheet sizing.
- [x] Validate scene transitions and APNs failure handling, retain notification coalescing/cursor regression checks.
- [x] Inspect full light/dark, large-type and iPad screens; test settings child/back, drawer, compose/search and category operations.
- [x] Build production source, document evidence and remaining real-device checks, then normal TF submission per authorized scope.

Reference patterns: Apple Settings grouped navigation/back hierarchy, Reminders category presentation. Apple HIG Sheets and Sidebars (checked 2026-11-24); system controls preserve Dynamic Type/VoiceOver and avoid color-only selection.
