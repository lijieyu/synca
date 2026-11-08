# Dialog quality implementation plan

Goal: Address the user's multi-platform polish checklist while retaining existing functionality and preview-only delivery.
Architecture: Keep current SwiftUI/AppKit and React components. Consolidate sizing and typography locally, use native iOS navigation for web documents, and preserve authenticated AI web-session isolation.

- [x] Native sheets: compact add-category affordance with accessible touch size; restrained category manager; Close copy; content-sensitive height; account Pro state without redundant title/date; text-only account actions; legal documents open internally without external-arrow symbols.
- [x] Web sheets: consistent compact/standard/read widths, 14px body and coherent heading scale, no empty footers; settings balanced rows, about identity leading; Pro state without purchase date/title.
- [x] AI: latest 3 operations initially, expand up to existing latest-50 endpoint; two-line connection timestamps, bottom-right revoke connection and footer; remove connected-app explanation; native iOS toolbar and embedded page chrome suppression.
- [x] Icon: preserve approved ribbon artwork, increase internal vertical breathing room and center optical weight; regenerate all assets.
- [x] Verify long Chinese/English, dark/light, free/Pro, short/tall content and narrow windows; compile iOS/Mac, web tests/build, relevant AI contract tests; capture real screenshots and deploy preview only.

No production deployment, no App Store Connect mutations, no automatic PR/merge in this polish task. Existing untracked certs/feedback uploads must not be staged.

Validation: Production iOS Simulator and macOS builds passed; 22 Vitest cases and 3 node test files passed; 315 native localization keys and InfoPlist parity passed; embedded AI trust tests passed. Actual isolated Mac app, iOS simulator and Chrome screenshots inspected, including Pro/free, native legal reader, category sheet sizing, short viewport scrolling and AI expand/collapse. Physical-device purchases and VoiceOver were not exercised.
