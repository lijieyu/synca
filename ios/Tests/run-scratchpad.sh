#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/synca-scratch-tests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -module-cache-path "$tmp/modules" "$root/ios/Synca/Shared/Core/SettingsManager.swift" "$root/ios/Synca/Shared/Models/AccessStatus.swift" "$root/ios/Synca/Shared/Models/SyncaMessage.swift" "$root/ios/Synca/Shared/Models/Scratchpad.swift" "$root/ios/Tests/ScratchpadTests.swift" -o "$tmp/tests"
"$tmp/tests"
