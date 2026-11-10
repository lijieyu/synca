#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/synca-markdown.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun swiftc -swift-version 6 -module-cache-path "$test_directory/module-cache" \
  "$project_root/ios/Synca/Shared/Views/MessageMarkdownRenderer.swift" \
  "$project_root/ios/Tests/MessageMarkdownTests.swift" \
  -o "$test_directory/message-markdown-tests"
"$test_directory/message-markdown-tests"
