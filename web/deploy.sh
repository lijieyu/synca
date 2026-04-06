#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Synca Web Frontend Deployment Script
# Builds locally, uploads to /opt/synca/web on ECS,
# and updates nginx to serve the SPA + proxy API
# ============================================================

REMOTE_HOST="root@123.56.247.129"
REMOTE_WEB_DIR="/opt/synca/web"

log() { echo -e "\n==> $*"; }

deploy_web() {
  log "Building web frontend..."
  npm run build

  log "Uploading dist to ${REMOTE_HOST}:${REMOTE_WEB_DIR}"
  ssh -o StrictHostKeyChecking=no "${REMOTE_HOST}" "mkdir -p ${REMOTE_WEB_DIR}"

  rsync -avzc --delete \
    -e "ssh -o StrictHostKeyChecking=no" \
    dist/ \
    "${REMOTE_HOST}:${REMOTE_WEB_DIR}/"

  log "Updating nginx config to serve SPA + proxy API..."
  ssh -o StrictHostKeyChecking=no "${REMOTE_HOST}" '
    NGINX_CONF="/etc/nginx/sites-enabled/synca-haerth-cn"
    
    # Backup current config
    cp "$NGINX_CONF" "${NGINX_CONF}.bak.$(date +%Y%m%d_%H%M%S)"

    cat > "$NGINX_CONF" << '\''NGINX'\''
server {
    server_name synca.haerth.cn;

    client_max_body_size 20m;

    root /opt/synca/web;
    index index.html;

    # API routes -> backend
    location /api {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /auth {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /messages {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /uploads {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /health {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /me {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /user-agreement {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /privacy-policy {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /support {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /feedback {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /access {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # SPA fallback: serve index.html for all other routes
    location / {
        try_files $uri $uri/ /index.html;
    }

    listen 172.26.29.139:443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/synca.haerth.cn/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/synca.haerth.cn/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
server {
    if ($host = synca.haerth.cn) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 172.26.29.139:80;
    server_name synca.haerth.cn;
    return 404; # managed by Certbot
}
NGINX

    # Test and reload nginx
    nginx -t && systemctl reload nginx
    echo "[nginx] Config updated and reloaded successfully!"
  '

  log "Web deployment complete! 🌐"
  log "Visit https://synca.haerth.cn to see the web app."
}

deploy_web
