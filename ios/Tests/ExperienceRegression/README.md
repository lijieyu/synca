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
