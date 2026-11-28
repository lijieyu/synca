#!/usr/bin/env bash
# Explicit opt-in: Preview uses real accounts and real data. Public Web stays unchanged.
# The existing isolated service retains the access gate/static files; its data is untouched.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
remote_host='root@123.56.247.129'
release_id="$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$project_root" rev-parse --short HEAD)-production-api"
release="/opt/synca-preview/routing-releases/$release_id"
ssh -o BatchMode=yes "$remote_host" "mkdir -p '$release'"
rsync -az -e 'ssh -o BatchMode=yes' "$project_root/scripts/preview-production-routing.py" "$remote_host:$release/"
ssh -o BatchMode=yes "$remote_host" bash -s -- "$release" <<'REMOTE'
set -euo pipefail
release="$1"
conf=/etc/nginx/sites-enabled/synca-preview
cp "$conf" "$release/previous.conf"
sha256sum /opt/synca/web/index.html > "$release/production-web.sha256"
python3 "$release/preview-production-routing.py" "$conf" "$release/next.conf"
rollback() {
  code=$?
  trap - ERR
  cp "$release/previous.conf" "$conf"
  nginx -t && systemctl reload nginx
  echo "Preview routing restored; production and isolated databases were not overwritten." >&2
  exit "$code"
}
trap rollback ERR
cp "$release/next.conf" "$conf"
nginx -t
systemctl reload nginx
python3 - <<'PY'
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import json
base='https://synca-preview.haerth.cn'
gate=Path('/opt/synca-preview/state/gate-token').read_text().strip()
def request(path, unlock=False):
    headers={'Accept':'application/json'}
    if unlock: headers['Cookie']='synca_preview_gate='+gate
    try:
        response=urlopen(Request(base+path,headers=headers),timeout=15)
    except HTTPError as error: response=error
    return response.status,response.headers.get('Content-Type',''),response.read()
for route in ['/auth/capabilities','/messages','/scratchpad','/sync/state']:
    assert request(route)[0]==401, 'Preview gate must protect API: '+route
for route in ['/messages','/scratchpad','/sync/state','/message-categories']:
    status,kind,body=request(route,True)
    assert status==401 and 'application/json' in kind, 'Product authentication required: '+route
    assert b'preview_access_required' not in body and b'preview_operation_disabled' not in body
status,kind,body=request('/auth/capabilities',True)
assert status==200 and 'email' in json.loads(body)
assert request('/__preview/production-gate',True)[0]==404
print('PASS: public TLS Preview access gate, production API routes, account authentication and internal-gate isolation')
PY
sha256sum -c "$release/production-web.sha256"
printf '%s\n' "$release" > /opt/synca-preview/current-production-routing
printf 'Preview production API routing active: %s\n' "$release"
REMOTE
bash "$project_root/scripts/deploy-preview-web.sh"
