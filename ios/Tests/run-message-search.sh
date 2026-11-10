#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/synca-search.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun swiftc -swift-version 6 -module-cache-path "$test_directory/module-cache" \
  "$project_root/ios/Synca/Shared/Core/SettingsManager.swift" \
  "$project_root/ios/Synca/Shared/Models/AccessStatus.swift" \
  "$project_root/ios/Synca/Shared/Models/SyncaMessage.swift" \
  "$project_root/ios/Synca/Shared/Utilities/MessageSearchIndex.swift" \
  "$project_root/ios/Tests/MessageSearchTests.swift" \
  -o "$test_directory/message-search-tests"
"$test_directory/message-search-tests"
