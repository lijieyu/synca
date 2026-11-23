#!/bin/bash
set -euo pipefail
plist="${1:?Expected root app Info.plist}"
# Reviewed standard cryptography, no France distribution. False means exempt
# from documentation, not that Electron/Chromium contains no encryption.
if [[ "$(/usr/bin/plutil -extract ITSAppUsesNonExemptEncryption raw -expect bool "$plist" 2>/dev/null)" != false ]]; then
  echo 'Missing or changed Mac export declaration; review before archiving.' >&2
  exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :ITSEncryptionExportComplianceCode' "$plist" >/dev/null 2>&1; then
  echo 'Unexpected export compliance code; review the declaration before archiving.' >&2
  exit 1
fi
