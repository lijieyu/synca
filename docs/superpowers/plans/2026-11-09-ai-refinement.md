# AI connection refinement implementation plan

**Goal:** Implement the approved compact AI demo across the shared React page and native WebView hosts.
**Spec:** Approved synca-ai-refinement.html demo in this conversation; user explicitly requested implementation.
**Architecture:** Keep existing authenticated API, clipboard prompt, OAuth consent and revoke flows. Replace presentation styles and tutorial layout; use a contained transition that preserves component state and respects reduced motion. Native hosts keep native navigation and pass application preferences.

- [x] Shared AI page: compact neutral layout, two-line connection metadata, trailing revoke with confirmation, three recent operations plus expand/collapse, concise localized tutorial and inline prompt disclosure.
- [x] Transitions: preserve expanded operations and scroll position on tutorial return, cancel interrupted animation, avoid initial-loading flash and honor reduced motion.
- [x] Native: compact Mac size, native close controls, app appearance/language propagation without changing auth/trust boundaries.
- [x] Verify actual UI using isolated mocked network, all three locales, 390/320px and desktop layouts, light/dark, errors, revoke cancel and confirm, tutorial return, reduced motion; build Web and native targets.

Keep pending category-color changes intact. No backend/data mutation, deployment or TF in this task.

## Verification evidence

- Web: 79 Vitest tests, 3 node test suites, production build, diff check passed.
- Native: iOS simulator Production and macOS Release builds passed; EmbeddedAISession trust/bootstrap/live preference tests passed.
- Actual H5 via isolated local API mocks: tutorial excludes management, return preserves 5 expanded operations, revoke cancel and one confirmed request, no-connections tutorial, error/reload, reduced-motion, three locales at 320/390/600 widths without overflow.
- Actual Web account-menu AI modal verified at 600px; light desktop and dark mobile H5 screenshots inspected. Native containers compiled, not visually or physically device-validated in this turn.
- No production APIs, account data, deployment, PR or TF changes.
