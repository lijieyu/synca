# iOS detail polish and regression fixes

## Included changes

- Category management: tap the name to edit, remove repeated pencil icons, keep the drag handle before the delete button, and preserve default-category protection and accessible move actions.
- Phone navigation: drawer follows the edge gesture; account chevron stays beside the account text. Keep all three header actions.
- Header: category name plus pending count, including zero; category-tinted background with neutral dark/light digits. All uses a neutral background.
- Account: identity, current plan, storage, sign out, then separate account deletion; plan details retain back navigation and large-text wrapping.
- Links: remove the legacy delegate that opened URLs for every interaction; preserve UIKit tap/open and long-press/copy behavior.
- Image completion: preserve a surviving neighboring record's viewport position, stable row identity, and the server write when navigation changes; failed requests must not leave artificial spacing.

## Verification reused for the submitted source

- All three changed view files and all three localization files byte-match the latest isolated UI fixture used for the approved light/dark screenshots.
- Phone detail walkthrough, category reorder and link long press passed. Two initial automation failures (large-text offscreen navigation and tapping whitespace in a wrapped link) were corrected in the test harness; both targeted reruns passed in `synca-ios-detail-recheck.xcresult`.
- Image completion and failure/navigation tests passed (`synca-ios-images-final.xcresult`, `synca-ios-images-boundary.xcresult`). The initial neighboring-row jump was approximately 402 pt; acceptance tolerance is 12 pt.
- iPad landscape frame and settings return passed (`synca-ios-detail-ipad-rotation.xcresult`). Capture orientation/cropping is unreliable, so those images are not visual acceptance evidence.
- Account ordering, plan navigation and appearance/large-text captures passed (`synca-account-order.xcresult`).
- Final neutral badge capture passed (`synca-category-badge-neutral.xcresult`), including category and zero states in light/dark appearance and preserved header actions.
- Shared macOS source build was verified during implementation. Final iOS fixture compilation passed; release metadata check confirms 1.2.0, launch screen and all iPad orientations. Cloud build number remains automatic.
- Tests use isolated example data and loopback responses. They do not establish live APNs, cross-device synchronization, or older-iOS link behavior; these remain device acceptance items.

## Release scope

Submit through the normal feature → dev → main PR flow for automatic TestFlight packaging. No production Web/backend deployment or email-login switch change. Cloud packaging and install availability are not claimed by local tests or PR merge.

## Device acceptance

1. Switch categories with 0 and nonzero pending records; check the header in both appearances and verify search/sync/clear stay reachable.
2. Open/close the drawer slowly and quickly; vertical scrolling must remain usable and drafts must stay intact.
3. Settings → Categories: tap to edit, drag to reorder, verify deletion controls and order after returning/reopening.
4. Settings → Account: verify identity → plan → storage → sign out order and back navigation from plan details.
5. Long-press a link to copy and tap to open; complete the lower record in an image-heavy feed without a large viewport jump, including slow-network navigation.
6. On iPad, rotate and return from settings; verify the layout directly on device.
