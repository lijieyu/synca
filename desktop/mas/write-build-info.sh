#!/bin/bash
set -euo pipefail
plist="${1:?Expected final bundle Info.plist}"
resources="${2:?Expected bundle Resources directory}"
# The final Xcode-processed bundle is authoritative, including Cloud build overrides.
app_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")
[[ "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]
printf '{"version":"%s","build":"%s"}\n' "$app_version" "$build_number" > "$resources/build-info.json"
