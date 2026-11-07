# Lifetime-only Pro implementation plan

Goal: Free + Pro one-time purchase, proposed mainland price CNY18. No production or App Store Connect mutation. No subscriber migration requested.
Architecture: Retain existing lifetime ID and transaction verification. Offer only lifetime in native catalog; keep historical receipt recognition. Web preview shows explicitly proposed CNY18 and cannot link to a real purchase at the unchanged CNY98 store price. Native purchasing always uses StoreKit displayPrice.
Tech stack: SwiftUI/StoreKit, React/i18next, isolated preview.

- [ ] Replace monthly/yearly purchase choices and upgrade offers; preserve restore.
- [ ] Update Simplified Chinese, Traditional Chinese and English copy and preview-only proposed-price notice.
- [ ] Test free/paid/unknown state, three languages and preview purchase isolation; compile both native targets.
- [ ] Review, deploy preview only, inspect actual preview and capture screenshot.

Review focus: no misleading real price; no subscription CTA; no repeated sale to paid account; localized long text; no production mutation.
