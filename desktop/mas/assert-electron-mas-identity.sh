#!/bin/bash
set -euo pipefail
app="${1:?Expected signed MAS application bundle}"
team="${2:?Expected Apple Developer Team ID}"
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid expected MAS team ID' >&2; exit 1; }
bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
[[ "$bundle" = org.haerth.synca ]] || { echo 'Invalid MAS bundle identifier' >&2; exit 1; }
plist_team=$(/usr/libexec/PlistBuddy -c 'Print :ElectronTeamID' "$app/Contents/Info.plist" 2>/dev/null || true)
[[ "$plist_team" = "$team" ]] || { echo 'Missing or incorrect required ElectronTeamID' >&2; exit 1; }
group=$(/usr/bin/codesign -d --entitlements - --xml "$app" 2>/dev/null | /usr/bin/plutil -extract com\\.apple\\.security\\.application-groups.0 raw -o - - 2>/dev/null || true)
[[ "$group" = "$team.$bundle" ]] || { echo 'Missing or incorrect required signed Electron MAS rendezvous group' >&2; exit 1; }
renderer="$app/Contents/Frameworks/Synca Helper (Renderer).app"
renderer_jit=$(/usr/bin/codesign -d --entitlements - --xml "$renderer" 2>/dev/null | /usr/bin/plutil -extract com\\.apple\\.security\\.cs\\.allow-jit raw -o - - 2>/dev/null || true)
[[ "$renderer_jit" = true ]] || { echo 'Missing required signed MAS renderer JIT entitlement' >&2; exit 1; }
