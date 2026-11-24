#!/usr/bin/env bash
set -euo pipefail

# Publish the exact, verified portable packages. Never rebuild or replace
# bytes at an existing URL. --check prepares/checks artifacts without network writes.
# Usage: scripts/deploy-windows-downloads.sh [--check] /path/to/synca-windows-public
mode=publish
if [ "${1:-}" = --check ]; then mode=check; shift; fi
if [ "$#" != 1 ] || [ ! -d "$1" ]; then
  echo 'Expected [--check] /path/to/synca-windows-public' >&2; exit 2
fi
source_dir="$(cd "$1" && pwd)"
release_id=1.2.0-20261125
remote_host=root@123.56.247.129
artifact="$(mktemp -d "${TMPDIR:-/tmp}/synca-windows-downloads.XXXXXX")"
trap 'rm -rf "$artifact"' EXIT

python3 - "$source_dir" "$artifact" <<'PY'
import hashlib,json,pathlib,shutil,struct,sys,zipfile
source,out=map(pathlib.Path,sys.argv[1:])
expected={
 'arm64':'b162e19e3eefe8f59cc5813358f59f3dd1d352f9c26bd84f2de2c1ec7b3ea6a1',
 'x64':'5a2f97965464385b55a8b2a92ef6f6363b8dbc3bbe79a65e5d29e4d01beda82d',
}
rows=[]
for arch,digest in expected.items():
 src=source/f'Synca-1.2.0-Windows-{arch}.zip'
 dest=out/f'Synca-1.2.0-Windows-{arch}.zip'
 shutil.copyfile(src,dest)
 h=hashlib.sha256()
 with dest.open('rb') as stream:
  for block in iter(lambda:stream.read(1024*1024),b''): h.update(block)
 if h.hexdigest()!=digest: raise SystemExit(f'Unreviewed package: {src.name}')
 with zipfile.ZipFile(dest) as archive:
  if archive.testzip() is not None: raise SystemExit(f'ZIP CRC failed: {src.name}')
  root=f'Synca Electron-win32-{arch}/'
  info=json.loads(archive.read(root+'resources/build-info.json'))
  if info!={'version':'1.2.0','build':'87'}: raise SystemExit('Unexpected package version')
  exe=archive.read(root+'Synca Electron.exe')
  pe=struct.unpack_from('<I',exe,0x3c)[0]
  if exe[pe:pe+4]!=b'PE\0\0' or struct.unpack_from('<H',exe,pe+4)[0]!={'arm64':0xaa64,'x64':0x8664}[arch]:
   raise SystemExit('Unexpected Windows executable architecture')
  if struct.unpack_from('<H',exe,pe+24)[0]!=0x20b or struct.unpack_from('<II',exe,pe+24+112+4*8)!=(0,0):
   raise SystemExit('Expected unsigned PE32+ portable build')
 rows.append(f'{digest}  {dest.name}\n')
(out/'SHA256SUMS.txt').write_text(''.join(rows))
print('Verified immutable Windows 1.2.0 (87), ARM64 and x64, including SHA-256, ZIP CRC and PE architecture.')
PY

if [ "$mode" = check ]; then
  cat "$artifact/SHA256SUMS.txt"
  echo 'Check only: no remote changes.'
  exit 0
fi

# Stage outside the public tree; checksum failure never publishes a partial file.
incoming="$(ssh -o BatchMode=yes "$remote_host" 'mkdir -p /opt/synca/download-staging && mktemp -d /opt/synca/download-staging/windows.XXXXXX')"
case "$incoming" in /opt/synca/download-staging/windows.[A-Za-z0-9]*) ;; *) echo 'Unexpected staging directory' >&2; exit 2 ;; esac
rsync -az -e 'ssh -o BatchMode=yes' "$artifact/" "$remote_host:$incoming/"
ssh -o BatchMode=yes "$remote_host" bash -s -- "$incoming" "$release_id" <<'REMOTE'
set -euo pipefail
incoming="$1"
release_id="$2"
test "$release_id" = 1.2.0-20261125
case "$incoming" in /opt/synca/download-staging/windows.[A-Za-z0-9]*) ;; *) exit 2 ;; esac
target="/opt/synca/downloads/windows/$release_id"
conf=/etc/nginx/sites-enabled/synca-haerth-cn
backup="$incoming/nginx.before.conf"
changed=0
rollback() {
  status=$?
  trap - ERR
  if [ "$changed" = 1 ]; then
    cp "$backup" "$conf"
    nginx -t && systemctl reload nginx
  fi
  echo "Download publication failed; nginx restored if changed. Verified artifacts retained; database and app untouched. Staging: $incoming" >&2
  exit "$status"
}
trap rollback ERR
(cd "$incoming" && sha256sum -c SHA256SUMS.txt)
mkdir -p "$(dirname "$target")"
if [ -e "$target" ]; then
  # Repeated publication is a no-op only when every published byte is identical.
  cmp "$incoming/SHA256SUMS.txt" "$target/SHA256SUMS.txt"
  (cd "$target" && sha256sum -c SHA256SUMS.txt)
else
  mkdir "$incoming/artifact"
  mv "$incoming"/*.zip "$incoming/SHA256SUMS.txt" "$incoming/artifact/"
  chmod 755 "$incoming/artifact"
  chmod 644 "$incoming/artifact/"*
  mv -T "$incoming/artifact" "$target"
fi
cp "$conf" "$backup"
python3 - "$conf" "$incoming/nginx.next.conf" <<'PY'
import pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
if 'server_name synca.haerth.cn;' not in source: raise SystemExit('Unexpected site')
block='''    # Immutable public Windows packages, independent from app and homepage releases.
    location ^~ /downloads/windows/ {
        alias /opt/synca/downloads/windows/;
        autoindex off;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

'''
marker='    # SPA fallback:'
if 'location ^~ /downloads/windows/' in source:
 if block not in source: raise SystemExit('Existing downloads route differs; inspect before changing')
elif 'location /downloads' in source or 'location ^~ /downloads' in source:
 raise SystemExit('Existing downloads route requires review')
else:
 if source.count(marker)!=1: raise SystemExit('Expected exactly one application fallback')
 source=source.replace(marker,block+marker,1)
pathlib.Path(sys.argv[2]).write_text(source)
PY
if ! cmp -s "$conf" "$incoming/nginx.next.conf"; then
  changed=1
  cp "$incoming/nginx.next.conf" "$conf"
  nginx -t
  systemctl reload nginx
fi
base="https://synca.haerth.cn/downloads/windows/$release_id"
# nginx reload is asynchronous: wait for a new worker to serve the exact bytes.
ready=0
for attempt in $(seq 1 10); do
  if curl -fsS --max-time 10 "$base/SHA256SUMS.txt" -o "$incoming/checksum.response" && cmp -s "$incoming/checksum.response" "$target/SHA256SUMS.txt"; then ready=1; break; fi
  sleep 1
done
test "$ready" = 1
for arch in arm64 x64; do
  name="Synca-1.2.0-Windows-$arch.zip"
  expected="$(sha256sum "$target/$name" | cut -d ' ' -f 1)"
  actual="$(curl -fsS --max-time 180 "$base/$name" | sha256sum | cut -d ' ' -f 1)"
  test "$actual" = "$expected"
done
missing="$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' "$base/not-a-package.zip")"
test "$missing" = 404
curl -fsS --max-time 15 https://synca.haerth.cn/health >/dev/null
trap - ERR
echo "Windows downloads active and public HTTPS bytes verified: $base/"
echo "nginx backup: $backup"
REMOTE
