#!/usr/bin/env bash
# Publish only the marketing page. Existing app, database and sessions stay untouched.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$project_root/web/public/home"
remote_host='root@123.56.247.129'
release_id="$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$project_root" rev-parse --short HEAD)"
release_dir="/opt/synca/home-releases/$release_id"
test -f "$source_dir/index.html"
test -f "$source_dir/en/index.html"
test -f "$source_dir/zh-Hant/index.html"
ssh -o BatchMode=yes "$remote_host" "mkdir -p '$release_dir'"
rsync -az -e 'ssh -o BatchMode=yes' "$source_dir/" "$remote_host:$release_dir/"
ssh -o BatchMode=yes "$remote_host" bash -s -- "$release_dir" <<'REMOTE'
set -euo pipefail
release_dir="$1"
case "$release_dir" in /opt/synca/home-releases/*) ;; *) exit 2 ;; esac
config='/etc/nginx/sites-enabled/synca-haerth-cn'
current='/opt/synca/home-current'
mkdir -p /opt/synca/home-backups
backup="/opt/synca/home-backups/$(basename "$release_dir").nginx.conf"
production_before="$(sha256sum /opt/synca/web/index.html)"
previous="$(readlink "$current" || true)"
cp "$config" "$backup"
rollback() {
  code=$?
  trap - ERR
  cp "$backup" "$config"
  if [ -n "$previous" ]; then ln -sfn "$previous" "$current"; else rm -f "$current"; fi
  nginx -t && systemctl reload nginx
  exit "$code"
}
trap rollback ERR
python3 - "$config" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
assert 'server_name synca.haerth.cn;' in s
marker='    location ^~ /home/ {'
if marker not in s:
    target='    # SPA fallback:'
    assert s.count(target)==1
    s=s.replace(target,'''    # Independent marketing page; root remains the existing application.
    location = /home { return 301 /home/; }
    location ^~ /home/ {
        alias /opt/synca/home-current/;
        index index.html;
        autoindex off;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Cache-Control "no-cache" always;
    }
'''+target)
    p.write_text(s)
else:
    assert 'alias /opt/synca/home-current/;' in s, 'Unexpected existing home route'
PY
ln -sfn "$release_dir" "$current"
nginx -t
systemctl reload nginx
for page in '' 'en/' 'zh-Hant/'; do
  curl -fsS --max-time 15 "https://synca.haerth.cn/home/$page" -o /dev/null
done
test "$production_before" = "$(sha256sum /opt/synca/web/index.html)"
trap - ERR
printf 'Marketing page active: %s\nExisting app index unchanged; only /home/ routing added.\n' "$release_dir"
REMOTE
