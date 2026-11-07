#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/synca-text-layout.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun swiftc -swift-version 6 -module-cache-path "$test_directory/module-cache" \
  "$project_root/ios/Synca/Shared/Views/MacPlainTextScrollView.swift" \
  "$project_root/ios/Tests/MacPlainTextLayoutTests.swift" \
  -o "$test_directory/mac-text-layout-tests"
"$test_directory/mac-text-layout-tests"
