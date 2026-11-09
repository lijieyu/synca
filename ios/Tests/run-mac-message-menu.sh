#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/synca-menu-tests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 6 -module-cache-path "$tmp/modules" \
 "$root/ios/Synca/Shared/Views/MacSelectableText.swift" \
 "$root/ios/Tests/MacMessageMenuTests.swift" -o "$tmp/tests"
"$tmp/tests"
