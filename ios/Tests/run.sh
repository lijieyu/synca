#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/synca-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun swiftc -module-cache-path "$test_directory/module-cache" \
  "$project_root/ios/Synca/Shared/Models/AccessStatus.swift" \
  "$project_root/ios/Synca/Shared/Models/SyncaMessage.swift" \
  "$project_root/ios/Tests/MessageListIndexTests.swift" \
  -o "$test_directory/message-index-tests"
"$test_directory/message-index-tests"
