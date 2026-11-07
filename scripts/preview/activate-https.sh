#!/usr/bin/env bash
# Run on the preview host after its DNS A record and certificate exist.
set -euo pipefail
preview_root=/opt/synca-preview
openssl x509 -in /etc/letsencrypt/live/synca-preview.haerth.cn/fullchain.pem -noout -checkhost synca-preview.haerth.cn
cp "$preview_root/nginx-active.conf" "$preview_root/nginx-active.backup"
cp "$preview_root/nginx-https.conf" "$preview_root/nginx-active.conf"
if ! nginx -t; then
  cp "$preview_root/nginx-active.backup" "$preview_root/nginx-active.conf"
  exit 1
fi
systemctl reload nginx
# Only remove this task's loopback-only test vhost, never another application's config.
if [ "$(readlink /etc/nginx/sites-enabled/synca-preview-local-check || true)" = "$preview_root/nginx-local-check.conf" ]; then
  rm /etc/nginx/sites-enabled/synca-preview-local-check
  nginx -t
  systemctl reload nginx
fi
sha256sum -c "$preview_root/production-baseline.sha256"
curl -fsS --max-time 10 https://synca.haerth.cn/health
