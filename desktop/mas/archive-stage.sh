#!/bin/bash
set -euo pipefail
: "${SYNCA_TF_PREPARED_APP:?The verified MAS app must exist before archiving}"
app="$SYNCA_TF_PREPARED_APP"
dst="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
"$SRCROOT/mas/assert-wrapper-metadata.sh" "$TARGET_BUILD_DIR/$INFOPLIST_PATH"
# Verify the Xcode-processed root plist, which is the one Apple receives.
/bin/bash "$SRCROOT/mas/assert-export-compliance.sh" "$TARGET_BUILD_DIR/$INFOPLIST_PATH"
root="$app/Contents"
test -d "$root"
test ! -d "$root/Frameworks/Squirrel.framework"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$root/Info.plist")" = org.haerth.synca
"$SRCROOT/mas/assert-ats-default.sh" "$root/Info.plist"
/bin/bash "$SRCROOT/mas/assert-export-compliance.sh" "$root/Info.plist"
icon=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$root/Info.plist")
[[ "$icon" =~ ^[A-Za-z0-9_.-]+\.icns$ ]]
"$SRCROOT/mas/icon.sh" verify "$root/Resources/$icon"
verify_stamp="$app/../synca-archive-variant.txt"
if [ "${CI:-}" = TRUE ] || [ "${CI:-}" = true ] || [ -n "${CI_BUILD_ID:-}" ]; then
  test -f "$verify_stamp" && grep -Eqx "verified-tf-(remote|production)" "$verify_stamp" || { echo 'TestFlight endpoint was not verified; refuse archive.' >&2; exit 1; }
fi
for d in Frameworks Library Resources; do
  if [ -d "$root/$d" ]; then
    /usr/bin/ditto "$root/$d" "$dst/Contents/$d"
  fi
done
/bin/bash "$SRCROOT/mas/write-build-info.sh" "$TARGET_BUILD_DIR/$INFOPLIST_PATH" "$dst/Contents/Resources"
/usr/bin/ditto "$root/MacOS/Synca" "$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
/usr/bin/cmp -s "$root/MacOS/Synca" "$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
  : "${EXPANDED_CODE_SIGN_IDENTITY:?No verified Xcode signing identity}"
  if [ -x "$SRCROOT/.mas-prepared/node/bin/node" ]; then
    export PATH="$SRCROOT/.mas-prepared/node/bin:$PATH"
  fi
  : "${DEVELOPMENT_TEAM:?No verified Xcode development team}"
  /usr/bin/env node "$SRCROOT/mas/archive-sign.mjs" "$dst" "$EXPANDED_CODE_SIGN_IDENTITY" "$DEVELOPMENT_TEAM"
  "$SRCROOT/mas/assert-electron-mas-identity.sh" "$dst" "$DEVELOPMENT_TEAM"
fi
