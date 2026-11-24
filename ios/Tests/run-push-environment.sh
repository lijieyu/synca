#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/synca-push-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun swiftc -module-cache-path "$test_directory/module-cache" \
  "$project_root/ios/Synca/Shared/Core/PushTokenManager.swift" \
  "$project_root/ios/Tests/PushEnvironmentTests.swift" -o "$test_directory/push-tests"
"$test_directory/push-tests"
