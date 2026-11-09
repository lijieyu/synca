# iOS scrolling regression fixture

This runs the real SwiftUI message list in an isolated test app. The generator
copies the current native source to a new temporary directory, replaces Keychain,
StoreKit observation and synchronization with local fixtures, and uses a generated
tall PNG. It does not read a real account, modify records or call production.
The bundle identifier is `org.haerth.synca.scrollqa`.

Requires Xcode, an iOS Simulator and XcodeGen:

```sh
python3 ios/Tests/ScrollRegression/make-fixture.py /tmp/synca-scroll-regression
xcodebuild -project /tmp/synca-scroll-regression/Synca.xcodeproj \
  -scheme Synca -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath /tmp/synca-scroll-regression-build \
  -resultBundlePath /tmp/synca-scroll-regression.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

Use a fresh destination/result path each run. Tests cover repeated last and
penultimate long-row collapse, repeated offscreen/on-screen images, removal of
source-device metadata, and the full-width new-category palette. A fixture-only
counter verifies that an already-loaded image never falls back to a placeholder.
Screenshots are attached to the result bundle.

This proves simulator behavior with deterministic local data, not physical-device
acceptance with a real account or network.
