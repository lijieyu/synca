#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/synca-update-tests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
python3 - "$root/ios/Synca/Shared/Core/AppUpdate.swift" "$tmp/Version.swift" <<'PY'
import sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
Path(sys.argv[2]).write_text('import Foundation\n'+text[text.index('enum AppVersion {'):text.index('@MainActor final class')])
PY
xcrun swiftc -module-cache-path "$tmp/modules" "$tmp/Version.swift" "$root/ios/Tests/AppVersionTests.swift" -o "$tmp/tests"
"$tmp/tests"
