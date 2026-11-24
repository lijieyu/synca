# Pro upgrade presentation implementation plan

Goal: implement the user-approved compact iOS upgrade screen, locally only.

Design: retain full free-plan/storage information in the account experience, show only current plan identity on the upgrade screen, use a single native surface with four Pro benefits, and group localized StoreKit price, buyout explanation, primary purchase action, restore and legal links. Retain the existing transaction and entitlement code. Paid-account and Mac-native presentations stay unchanged. Dynamic Type can scroll; no hard single-screen height.

- [x] Replace the iOS free/trial presentation in AccessCenterView; preserve navigation, recovery and purchases.
- [x] Add concise localized benefit detail/action labels and reserved purchase-state space.
- [x] Use an isolated StoreKit test configuration to inspect normal price and failure states, light/dark, plus large text. No actual purchases.
- [x] Review full screenshots, run affected build/UI checks, report exact verification scope without releasing.

## Verification

- Native build and `testUpgradePresentation` passed on reused iPhone 17 / iOS 27.0: six modes, zero failures, 168 seconds. Result: `/private/tmp/synca-upgrade-polish-v4.xcresult`.
- Inspected seven full native screenshots: light/dark normal price, light/dark unavailable product, maximum accessibility text at top and actions, and English. Primary and restore actions remain reachable, close returns to Connect AI.
- The local StoreKit fixture returned CNY 98.00; this is test data, not an online price change. Purchase/restore methods are retained; this task did not submit a transaction or establish real-store purchasing.
- Independent read-only review identified explicit restore-button accent color; new iOS call now uses primary color. Restore/legal labels have 44pt hit regions; old Mac defaults preserved.
- Initial test identifiers were overwritten by a parent accessibility identifier; removed parent identifier. Final rerun passed. One intermediate run was interrupted before final source validation and is not completion evidence.
- Release metadata check and diff whitespace check passed; all eight new strings match across Simplified Chinese, Traditional Chinese and English.
- Comparison gallery: `/Users/haer/Documents/Codex/2026-11-24/synca-pro-upgrade/index.html`.
- Loopback service stopped; the simulator is shut down. No commit, push, deployment or TF triggered.
