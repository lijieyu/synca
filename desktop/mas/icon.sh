#!/bin/bash
set -euo pipefail
mode="${1:?Expected create or verify}"
out="${2:?Expected target ICNS}"
work=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/synca-mas-icon.XXXXXX")
trap '/bin/rm -rf -- "$work"' EXIT
valid_size(){
  /usr/bin/sips -g pixelWidth -g pixelHeight "$1" | /usr/bin/awk -v n="$2" '$1=="pixelWidth:"{w=$2}$1=="pixelHeight:"{h=$2}END{exit !(w==n&&h==n)}'
}
case "$mode" in
  create)
    src="${3:?Expected canonical 1024 macOS source art}"
    valid_size "$src" 1024 || { echo 'Exact native 1024px master icon required, no upscaling.' >&2; exit 1; }
    /bin/mkdir "$work/Synca.iconset"
    for points in 16 32 128 256 512; do
      for scale in 1 2; do
        size=$((points*scale))
        suffix=""
        [[ "$scale" = 1 ]] || suffix="@2x"
        name="$work/Synca.iconset/icon_${points}x${points}${suffix}.png"
        if [[ "$size" = 1024 ]]; then /bin/cp "$src" "$name"
        else /usr/bin/sips -z "$size" "$size" "$src" --out "$name" >/dev/null; fi
      done
    done
    /usr/bin/iconutil -c icns "$work/Synca.iconset" -o "$out"
    ;;
  verify) ;;
  *) exit 2 ;;
esac
/usr/bin/iconutil -c iconset "$out" -o "$work/readback.iconset"
big="$work/readback.iconset/icon_512x512@2x.png"
[[ -f "$big" ]] && valid_size "$big" 1024 || { echo 'ICNS lacks a true 512pt x 512pt @2x image.' >&2; exit 1; }
