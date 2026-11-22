#!/bin/bash
set -euo pipefail
: "${SYNCA_TF_PREPARED_APP:?The verified MAS app must exist before archiving}"
app="$SYNCA_TF_PREPARED_APP"
dst="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
root="$app/Contents"
test -d "$root"
test ! -d "$root/Frameworks/Squirrel.framework"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$root/Info.plist")" = org.haerth.synca
"$SRCROOT/mas/assert-ats-default.sh" "$root/Info.plist"
verify_stamp="$app/../synca-archive-variant.txt"
if [ "${CI:-}" = TRUE ] || [ "${CI:-}" = true ] || [ -n "${CI_BUILD_ID:-}" ]; then
  test -f "$verify_stamp" && grep -qx "verified-tf-remote" "$verify_stamp" || { echo 'Remote TestFlight endpoint was not verified; refuse archive.' >&2; exit 1; }
fi
for d in Frameworks Library Resources; do
  if [ -d "$root/$d" ]; then
    /usr/bin/ditto "$root/$d" "$dst/Contents/$d"
  fi
done
/usr/bin/ditto "$root/MacOS/Synca" "$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
/usr/bin/cmp -s "$root/MacOS/Synca" "$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
  : "${EXPANDED_CODE_SIGN_IDENTITY:?No verified Xcode signing identity}"
  if [ -x "$SRCROOT/.mas-prepared/node/bin/node" ]; then
    export PATH="$SRCROOT/.mas-prepared/node/bin:$PATH"
  fi
  /usr/bin/env node "$SRCROOT/mas/archive-sign.mjs" "$dst" "$EXPANDED_CODE_SIGN_IDENTITY"
fi
