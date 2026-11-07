#!/usr/bin/env bash
# Isolated preview deployment. Never calls deploy-release.sh or changes /opt/synca/web.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_host='root@123.56.247.129'
release_id="$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$project_root" rev-parse --short HEAD)-preview"
release_path="/opt/synca-preview/releases/$release_id"
npm --prefix "$project_root/backend" run build
VITE_PREVIEW_PRICING=true npm --prefix "$project_root/web" run build
artifact="$(mktemp -d)"
trap 'rm -rf "$artifact"' EXIT
mkdir -p "$artifact/backend"
cp -R "$project_root/backend/dist" "$artifact/backend/dist"
cp -R "$project_root/backend/certs" "$artifact/certs"
cp "$project_root/backend/package.json" "$project_root/backend/package-lock.json" "$artifact/"
cp -R "$project_root/web/dist" "$artifact/web"
cp "$project_root/scripts/preview/"* "$artifact/"
python3 - "$artifact" <<'PY'
import sys
from pathlib import Path
root=Path(sys.argv[1])
for page in [root/'web/index.html',root/'web/ai/index.html']:
    html=page.read_text().replace('<head>','<head><meta name="robots" content="noindex,nofollow"><script src="/__preview/bootstrap.js"></script>',1)
    page.write_text(html)
PY
ssh -o BatchMode=yes "$preview_host" "mkdir -p '$release_path' /opt/synca-preview/state/data /var/www/synca-preview-acme"
rsync -az -e 'ssh -o BatchMode=yes' "$artifact/" "$preview_host:$release_path/"
ssh -o BatchMode=yes "$preview_host" bash -s -- "$release_path" <<'REMOTE'
set -euo pipefail
release="$1"
case "$release" in /opt/synca-preview/releases/*) ;; *) exit 2 ;; esac
# Install preview dependencies in the immutable preview release, never in the live backend.
(cd "$release" && npm ci --omit=dev --no-audit --no-fund)
cp -R "$release/certs" /opt/synca-preview/state/
export PREVIEW_RELEASE_PATH="$release"
node --input-type=module <<'JS'
import fs from 'node:fs';
const release=process.env.PREVIEW_RELEASE_PATH;
fs.writeFileSync(`${release}/ecosystem.config.cjs`, `module.exports = ${JSON.stringify({apps:[{name:'synca-preview',script:`${release}/server.mjs`,cwd:'/opt/synca-preview/state',instances:1,exec_mode:'fork',max_memory_restart:'384M',env:{NODE_ENV:'production',DB_PATH:'/opt/synca-preview/state/data/preview.sqlite',APNS_ENABLED:'false',PUBLIC_URL:'https://synca-preview.haerth.cn'}}]},null,2)};`);
JS
pm2 delete synca-preview >/dev/null 2>&1 || true
pm2 start "$release/ecosystem.config.cjs" --only synca-preview
healthy=0
for attempt in $(seq 1 15); do
  if curl -fsS --max-time 2 -H 'Host: synca-preview.haerth.cn' -b "synca_preview_gate=$(cat /opt/synca-preview/state/gate-token 2>/dev/null)" http://127.0.0.1:3004/health >/dev/null; then healthy=1; break; fi
  sleep 1
done
if [ "$healthy" != 1 ]; then pm2 stop synca-preview; exit 1; fi
ln -sfn "$release" /opt/synca-preview/current
pm2 save
printf 'Preview artifact active: %s\n' "$release"
REMOTE
