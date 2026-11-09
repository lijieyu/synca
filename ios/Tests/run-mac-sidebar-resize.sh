#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/synca-sidebar-tests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
# Compile the real resize handle without unrelated main-window controllers.
python3 - "$root" "$tmp" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'ios/Synca/macOS/MacWindowBehavior.swift').read_text()
start=source.index('struct MacSidebarResizeHandle:')
end=source.index('/// Same single text bubble',start)
(Path(sys.argv[2])/'Handle.swift').write_text('import AppKit\nimport SwiftUI\n'+source[start:end])
PY
xcrun swiftc -swift-version 6 -module-cache-path "$tmp/modules" "$tmp/Handle.swift" "$root/ios/Tests/MacSidebarResizeTests.swift" -o "$tmp/tests"
"$tmp/tests"
