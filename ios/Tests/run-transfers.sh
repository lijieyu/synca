#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/synca-transfers.XXXXXX")"
fixture_pid=""
cleanup() { if [[ -n "$fixture_pid" ]]; then kill "$fixture_pid" 2>/dev/null || true; fi; rm -rf "$test_directory"; }
trap cleanup EXIT
if [[ "${SYNCA_TEST_EXISTING_FIXTURE:-0}" != "1" ]]; then
  node "$project_root/ios/Tests/fixtures/media-server.mjs" > "$test_directory/server.log" 2>&1 &
  fixture_pid=$!
fi
for attempt in {1..50}; do
  if /usr/bin/curl -s http://127.0.0.1:3000/ >/dev/null; then break; fi
  sleep 0.1
done
if [[ -n "$fixture_pid" ]] && ! kill -0 "$fixture_pid" 2>/dev/null; then cat "$test_directory/server.log"; exit 1; fi
xcrun swiftc -swift-version 6 -module-cache-path "$test_directory/module-cache" \
  "$project_root/ios/Synca/Shared/Models/AccessStatus.swift" \
  "$project_root/ios/Synca/Shared/Models/SyncaMessage.swift" \
  "$project_root/ios/Synca/Shared/Core/APIClient.swift" \
  "$project_root/ios/Synca/Shared/Core/ImageCacheManager.swift" \
  "$project_root/ios/Tests/NativeTransferTests.swift" \
  -o "$test_directory/transfer-tests"
"$test_directory/transfer-tests"
