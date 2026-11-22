#!/bin/bash
set -euo pipefail
p="${1:?Expected actual xcodebuild-processed Info.plist}"
read_key(){ /usr/libexec/PlistBuddy -c "Print :$1" "$p"; }
expect(){
  actual=$(read_key "$1")
  if [[ "$actual" != "$2" ]]; then
    printf 'Invalid generated wrapper metadata %s: expected %s, got %s\n' "$1" "$2" "$actual" >&2
    exit 1
  fi
}
/usr/bin/plutil -lint "$p" >/dev/null
sdk_build=$(/usr/bin/xcrun --sdk macosx --show-sdk-build-version)
sdk_version=$(/usr/bin/xcrun --sdk macosx --show-sdk-version)
xcode_build=$(/usr/bin/xcodebuild -version | /usr/bin/awk '/^Build version / {print $3}')
mac_build=$(/usr/bin/sw_vers -buildVersion)
test -n "$sdk_build" && test -n "$sdk_version" && test -n "$xcode_build" && test -n "$mac_build"
expect BuildMachineOSBuild "$mac_build"
expect DTPlatformBuild "$sdk_build"
expect DTSDKBuild "$sdk_build"
expect DTSDKName "macosx$sdk_version"
expect DTXcodeBuild "$xcode_build"
expect DTPlatformName macosx
