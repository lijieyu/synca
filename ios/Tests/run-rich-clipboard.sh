#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/synca-clipboard-tests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 6 -module-cache-path "$tmp/modules" \
 "$root/ios/Synca/Shared/Utilities/RichClipboardText.swift" \
 "$root/ios/Synca/Shared/Core/SettingsManager.swift" \
 "$root/ios/Synca/Shared/Models/AccessStatus.swift" \
 "$root/ios/Synca/Shared/Models/SyncaMessage.swift" \
 "$root/ios/Synca/Shared/Views/MacInputTextView.swift" \
 "$root/ios/Tests/RichClipboardTextTests.swift" -o "$tmp/tests"
"$tmp/tests"
