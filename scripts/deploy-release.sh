#!/usr/bin/env bash
set -euo pipefail

# Upload into an immutable release, preserve live data/config, then switch code.
# Usage: scripts/deploy-release.sh [all|backend|web]
target="${1:-all}"
case "$target" in all|backend|web) ;; *) echo 'Expected all, backend or web' >&2; exit 2 ;; esac
project_root="$(cd "$(dirname "$0")/.." && pwd)"
remote_host="root@123.56.247.129"
revision="$(git -C "$project_root" rev-parse --short HEAD)"
release_id="$(date -u +%Y%m%dT%H%M%SZ)-${revision}"
release_path="/opt/synca/releases/${release_id}"

if [ "$target" != web ]; then npm --prefix "$project_root/backend" run build; fi
if [ "$target" != backend ]; then npm --prefix "$project_root/web" run build; fi
ssh -o BatchMode=yes "$remote_host" "mkdir -p '$release_path/backend' '$release_path/web' '$release_path/backup'"
if [ "$target" != web ]; then
  rsync -az -e 'ssh -o BatchMode=yes' "$project_root/backend/dist" "$project_root/backend/package.json" "$project_root/backend/package-lock.json" "$remote_host:$release_path/backend/"
fi
if [ "$target" != backend ]; then
  rsync -az -e 'ssh -o BatchMode=yes' "$project_root/web/dist/" "$remote_host:$release_path/web/"
fi
ssh -o BatchMode=yes "$remote_host" bash -s -- "$release_id" "$target" <<'REMOTE'
set -euo pipefail
release_id="$1"
target="$2"
release="/opt/synca/releases/$release_id"
backend="/opt/synca/backend"
web="/opt/synca/web"
nginx_conf="/etc/nginx/sites-enabled/synca-haerth-cn"
backend_switched=0
web_switched=0
nginx_switched=0

rollback() {
  code=$?
  trap - ERR
  set +e
  if [ "$backend_switched" = 1 ]; then
    rm "$backend/dist"
    mv "$release/backup/backend-dist" "$backend/dist"
    pm2 restart synca-api
  fi
  if [ "$web_switched" = 1 ]; then
    rm "$web"
    mv "$release/backup/web" "$web"
  fi
  if [ "$nginx_switched" = 1 ]; then
    cp "$release/backup/nginx.conf" "$nginx_conf"
    nginx -t && systemctl reload nginx
  fi
  echo "Release failed; code/config restored. Database was NOT overwritten. Backup: $release/backup" >&2
  exit "$code"
}
trap rollback ERR

cp "$nginx_conf" "$release/backup/nginx.conf"
if [ "$target" != web ]; then
  # Reuse installed dependencies only when both manifests match exactly.
  # Dependency updates are prepared in staging, never installed over a running app.
  if cmp -s "$backend/package-lock.json" "$release/backend/package-lock.json" && cmp -s "$backend/package.json" "$release/backend/package.json"; then
    ln -s "$(readlink -f "$backend/node_modules")" "$release/backend/node_modules"
  else
    (cd "$release/backend" && npm ci --omit=dev)
  fi
  cd "$backend"
  SYNCA_RELEASE_BACKUP="$release/backup/database.sqlite" node --input-type=module <<'NODE'
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import dotenv from 'dotenv';
import SQLite from 'better-sqlite3';
const env = dotenv.parse(fs.readFileSync('.env'));
// Detect a missing/invalid push key before switching a healthy running service.
if (String(env.APNS_ENABLED ?? '').toLowerCase() === 'true') {
  for (const name of ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC']) {
    if (!env[name]?.trim()) throw new Error(`Missing required push setting: ${name}`);
  }
  const pem = env.APNS_AUTH_KEY?.trim() || fs.readFileSync(env.APNS_AUTH_KEY_PATH?.trim() || '', 'utf8');
  const key = crypto.createPrivateKey(pem.replace(/\\n/g, '\n'));
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('APNS signing key must be P-256');
  }
  console.log('APNS signing key is present and valid.');
}
const configured = env.DB_PATH?.trim();
const source = configured ? (path.isAbsolute(configured) ? configured : path.resolve('data', configured)) : path.resolve('data/synca.sqlite');
const database = new SQLite(source, { readonly: true, fileMustExist: true });
await database.backup(process.env.SYNCA_RELEASE_BACKUP);
database.close();
console.log('Consistent SQLite backup completed.');
NODE
  # Additive migrations run before activation and honor the existing .env.
  node --import dotenv/config "$release/backend/dist/src/migrate.js"
  mv "$backend/dist" "$release/backup/backend-dist"
  backend_switched=1
  ln -s "$release/backend/dist" "$backend/dist"
  pm2 restart synca-api
  healthy=0
  for attempt in $(seq 1 15); do
    if curl -fsS --max-time 3 http://127.0.0.1:3002/health >/dev/null; then healthy=1; break; fi
    sleep 1
  done
  test "$healthy" = 1
fi
if [ "$target" != backend ]; then
  mv "$web" "$release/backup/web"
  web_switched=1
  ln -s "$release/web" "$web"
fi
# Modify only this application's existing server block, preserving TLS/listen settings.
python3 - "$nginx_conf" "$release/nginx.conf" <<'PY'
import re,sys
from pathlib import Path
source=Path(sys.argv[1]).read_text()
if 'server_name synca.haerth.cn;' not in source:
    raise SystemExit('Unexpected nginx server; refusing to edit')
source,n=re.subn(r'client_max_body_size\s+[^;]+;', 'client_max_body_size 210m;', source, count=1)
if n!=1: raise SystemExit('Missing body limit; review config before deploying')
for name in ['client_body_timeout','proxy_read_timeout','proxy_send_timeout']:
    if re.search(r'\b'+name+r'\s+[^;]+;', source):
        source=re.sub(r'\b'+name+r'\s+[^;]+;',name+' 900s;',source)
    else: source=source.replace('client_max_body_size 210m;', 'client_max_body_size 210m;\n    '+name+' 900s;',1)
if 'proxy_request_buffering off;' not in source:
    source=source.replace('location /messages {','location /messages {\n        proxy_request_buffering off;',1)
if 'location /message-categories {' not in source:
    start=source.index('    location /messages {')
    end=source.index('\n    }',start)+6
    block=source[start:end].replace('location /messages {','location /message-categories {').replace('        proxy_request_buffering off;\n','')
    source=source[:end]+'\n\n'+block+source[end:]
if 'location ~ ^/(en|zh-hans)/' in source:
    source=source.replace('(privacy-policy|user-agreement|support)', '(privacy-policy|terms-of-use|support)')
else:
    position=source.index('    # SPA fallback:')
    source=source[:position]+'''    location ~ ^/(en|zh-hans)/(privacy-policy|terms-of-use|support)$ {
        proxy_pass http://127.0.0.1:3002;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

'''+source[position:]
# MCP and OAuth must reach the API rather than the SPA fallback.
for route in ['/mcp', '/api/ai/', '/oauth/', '/.well-known/oauth-']:
    marker='location ^~ '+route+' {'
    if marker not in source:
        position=source.index('    # SPA fallback:')
        source=source[:position]+('    '+marker+'\n'
            '        proxy_pass http://127.0.0.1:3002;\n'
            '        proxy_http_version 1.1;\n'
            '        proxy_buffering off;\n'
            '        proxy_set_header Host $host;\n'
            '        proxy_set_header X-Real-IP $remote_addr;\n'
            '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n'
            '        proxy_set_header X-Forwarded-Proto $scheme;\n'
            '    }\n\n')+source[position:]
if 'location ^~ /files/' not in source:
    position=source.index('    # SPA fallback:')
    source=source[:position]+'''    # Documents are served exclusively by the authenticated API.
    location ^~ /files/ { return 404; }

'''+source[position:]
Path(sys.argv[2]).write_text(source)
PY
cp "$release/nginx.conf" "$nginx_conf"
nginx_switched=1
nginx -t
systemctl reload nginx
curl -fsS --max-time 10 https://synca.haerth.cn/health >/dev/null
status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' https://synca.haerth.cn/message-categories)"
test "$status" = 401
pm2 save
printf '%s\n' "$release_id" > /opt/synca/current-release
trap - ERR
echo "Release active: $release_id; backups: $release/backup"
REMOTE
printf 'Deployed release: %s\n' "$release_id"
