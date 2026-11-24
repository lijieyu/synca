#!/bin/bash
set -euo pipefail
plist="${1:?Expected signed root entitlements plist or stdin}"
environment=$(/usr/bin/plutil -extract com\\.apple\\.developer\\.aps-environment raw -o - "$plist" 2>/dev/null || true)
[[ "$environment" = production ]] || { echo 'Mac archive is missing the production APNs entitlement.' >&2; exit 1; }
