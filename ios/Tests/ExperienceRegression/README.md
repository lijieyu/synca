# iOS experience regression fixtures

This copies current product source into an isolated temporary app (`org.haerth.synca.iospolishqa`). It never reads real Keychain credentials and never calls production. Requires Xcode, XcodeGen and an existing iOS simulator. Reuse the existing phone/iPad, one running device at a time; shut down after testing.

Generate in a **new** destination:

```sh
python3 ios/Tests/ExperienceRegression/make-fixture.py /tmp/synca-ui
# Or actual SyncManager/APIClient/AppDelegate with intercepted HTTP:
python3 ios/Tests/ExperienceRegression/make-fixture.py /tmp/synca-sync --integration
xcodebuild -project /tmp/synca-sync/Synca.xcodeproj -scheme Synca \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath /tmp/synca-sync-build CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO -resultBundlePath /tmp/synca-sync.xcresult test
```

The visual fixture seeds example records and disables network sync/StoreKit observation. UI tests cover phone drawer, three header buttons, draft preservation, settings children/back, plan navigation, feedback, search, dark mode, largest Dynamic Type and iPad landscape. Run only the phone tests on phone; run `testIPadLandscape` on iPad. UI screenshots alone do not establish synchronization correctness.

For `testAIPlans`, build the unchanged Web frontend into a temporary output directory using Vite, then run `python3 ios/Tests/ExperienceRegression/serve-ai.py /tmp/WEB_OUTPUT`. The server binds only loopback port 54671 and returns example free/Pro rights. The fixture permits that origin only. Stop this server after testing. This validates the real shared AI interface inside the native settings hierarchy without a live user session.

The hosted integration test retains real synchronization code and intercepts all HTTP with URLProtocol. It checks token re-registration after environment migration, no duplicate upload, full baseline, incremental add/edit/delete/category/count, APNs callback result and failure preserving data. This does **not** establish actual APNs delivery, background wake or the SpringBoard badge on a signed device; those require TestFlight device acceptance.

## Category, link and completion regression (2026-11-24)

Generate regular and image fixtures in separate new directories. Use the loopback interaction server while running category writes or image tests (do not run it alongside serve-ai.py, which uses the same port):

```sh
python3 ios/Tests/ExperienceRegression/make-fixture.py /tmp/synca-images --images
python3 ios/Tests/ExperienceRegression/serve-interactions.py /tmp/synca-images/fixture-records.json
```

Run `testDrawerAndCategoryEditing`, `testDetailDarkAndLargeType`, `testLinkLongPress`, `testLinkTap`, and `testWalkthrough` on the regular fixture. Run `testImageCompletion` and `testImageCompletionFailureAndNavigation` on the image fixture. Run only `testIPadLandscape` on the existing iPad. Always disable parallel simulator testing and stop the loopback server afterward.

The image tests exercise the real completion method against loopback responses. They compare the same surviving record before/after completion (12pt tolerance), preserve incomplete state on an HTTP failure, and confirm that navigating during a delayed response does not cancel the write. They do not prove cross-device or production synchronization. For wrapped links, tap an actual glyph rather than the empty center of the multi-line accessibility rectangle.

Results: 8 targeted UI tests passed across the existing iPhone 17 and iPad Pro 13-inch (M5), iOS 27.0. The original image-completion case moved the neighboring record by about 402pt. Removing the legacy UITextView delegate fixes its unconditional URL-opening path; the old long-press failure did not reproduce on iOS 27 before removal, so older-system behavior still needs real-device coverage. The shared macOS source also built successfully. No release was triggered.

Local screenshots and comparison: `/Users/haer/Documents/Codex/2026-11-24/synca-ios-detail/comparison.html`.

The iPad rotation test asserts the actual application frame is wider than tall. Screenshot export still exhibited orientation/cropping inconsistencies with the simulator capture API, so iPad captures are excluded from the visual comparison; device visual acceptance remains necessary.

## Pro upgrade presentation (2026-11-24)

`testUpgradePresentation` uses the loopback AI service and bundled `UpgradePreview.storekit` through `SKTestSession`. It checks the native upgrade sheet opened from Connect AI in light/dark, product-unavailable light/dark, maximum accessibility text, and English. The test product price is fixture-only (CNY 98.00), not a change to App Store pricing. No purchase or restore transaction is submitted. It checks product display, reachable primary/restore actions and close returning to the AI page.

The fixture-only `-qa-products-unavailable` launch argument skips loading products to exercise the error layout; this switch is never added to product source. The product page continues to call the existing PurchaseManager transaction methods.
