#!/bin/bash
set -euo pipefail
: "${CI_PRIMARY_REPOSITORY_PATH:?Use only within the dedicated Apple Xcode Cloud workflow}"
cd "$CI_PRIMARY_REPOSITORY_PATH/desktop"
# Production was explicitly authorized for the new Mac build; isolated builds remain opt-in.
case "${SYNCA_TF_MODE:-production}" in
 production) release=mas/production-release.json; build_mode=--verified-production ;;
 isolated) release=mas/testflight-release.json; build_mode=--verified-testflight ;;
 *) echo 'Unknown TF mode; no archive.' >&2; exit 78 ;;
esac
test -f "$release" || { echo 'Exact verified backend release missing; no archive or upload.' >&2; exit 78; }
# The operator verifies these exact stable versions in the dedicated workflow too.
mac_build=$(/usr/bin/sw_vers -buildVersion)
xcode_build=$(/usr/bin/xcodebuild -version | /usr/bin/awk '/^Build version / { print $3 }')
if [[ "$mac_build" != 26B131 || "$xcode_build" != 27B52 ]]; then
  printf 'Wrong Mac TestFlight toolchain; expected macOS 26B131/Xcode 27B52, got %s/%s. No archive or upload.\n' "$mac_build" "$xcode_build" >&2
  exit 78
fi
case "$(/usr/bin/uname -m)" in
  arm64) node_arch=arm64; expected=d5c37f04d4006741574730871148839f254f3b3940f5afd70f7d1e70970c90e3 ;;
  x86_64) node_arch=x64; expected=7b6211bdb2a90834422f0243274ff1ca5deee309ca12a21329edcf1f775f8113 ;;
  *) echo 'Unsupported Xcode Cloud Mac architecture.' >&2; exit 1 ;;
esac
root="$PWD/.mas-prepared"
test ! -e "$root" || { echo 'Refusing reused Cloud build inputs.' >&2; exit 1; }
umask 077
mkdir -p "$root/node" "$root/runtime"
node_file="node-v25.6.1-darwin-$node_arch.tar.xz"
curl -fsSL --proto '=https' --max-time 240 "https://nodejs.org/dist/v25.6.1/$node_file" -o "$root/$node_file"
printf '%s  %s\n' "$expected" "$root/$node_file" | /usr/bin/shasum -a 256 -c -
/usr/bin/tar -xJf "$root/$node_file" -C "$root/node" --strip-components 1
export PATH="$root/node/bin:$PATH"
export npm_config_registry=https://registry.npmjs.org/
npm ci --ignore-scripts --no-fund --no-audit
(cd ../web && npm ci --ignore-scripts --no-fund --no-audit)
version=$(node -p 'require("./package.json").devDependencies.electron')
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
for arch in arm64 x64; do
  zip="electron-v$version-mas-$arch.zip"
  curl -fsSL --proto '=https' --max-time 300 "https://github.com/electron/electron/releases/download/v$version/$zip" -o "$root/runtime/$zip"
done
node --test mas-preflight.test.cjs mas/gate.test.cjs mas/release-config.test.cjs preview-config.test.cjs
npm run build:ui
SYNCA_MAS_RUNTIME_DIR="$root/runtime" SYNCA_MAS_PREFLIGHT_OUT="$root" node build-mas-preflight.mjs "$build_mode"
