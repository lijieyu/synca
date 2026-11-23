#!/bin/bash
set -euo pipefail
plist="${1:?Expected built Electron app Info.plist}"
/usr/bin/plutil -lint "$plist" >/dev/null
if /usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity' "$plist" > /dev/null 2>&1; then
  settings=$(/usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity' "$plist")
  if [[ "$settings" != $'Dict {\n}' ]]; then
    echo 'Unexpected ATS exceptions in the Electron TestFlight payload.' >&2
    exit 1
  fi
fi
