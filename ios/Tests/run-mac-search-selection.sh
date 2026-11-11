#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/synca-search-selection.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
# Compile the production AppKit representable without the unrelated search panel.
python3 - "$root" "$tmp" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'ios/Synca/Shared/Views/MessageSearchView.swift').read_text()
field=source[source.index('private struct SearchQueryField: NSViewRepresentable'):].rsplit('#endif',1)[0]
(Path(sys.argv[2])/'Field.swift').write_text('import SwiftUI\nimport AppKit\n'+field.replace('private struct SearchQueryField','struct SearchQueryField',1))
PY
xcrun swiftc -parse-as-library -swift-version 6 -module-cache-path "$tmp/modules" \
  "$tmp/Field.swift" "$root/ios/Tests/MacSearchSelectionTests.swift" -o "$tmp/tests"
"$tmp/tests"
