#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Synca Backend Deployment Script
# Target: /opt/synca/backend on Alibaba Cloud ECS
# SAFE: Only touches /opt/synca/, does NOT touch everbond
# ============================================================

REMOTE_HOST="root@123.56.247.129"
REMOTE_DIR="/opt/synca/backend"
PM2_APP_NAME="synca-api"
SYNCA_PORT=3002

log() { echo -e "\n==> $*"; }

deploy() {
  log "Building backend project..."
  rm -rf dist
  npm run build

  log "Syncing files to ${REMOTE_HOST}:${REMOTE_DIR}"
  log "⚠️  Only touching /opt/synca/ — everbond is safe"

  # First ensure the directory exists (don't rsync --delete on first deploy)
  ssh -o StrictHostKeyChecking=no "${REMOTE_HOST}" "mkdir -p ${REMOTE_DIR}"

  rsync -avzc \
    -e "ssh -o StrictHostKeyChecking=no" \
    --delete \
    --exclude '/node_modules' \
    --exclude '/.git' \
    --exclude '/tests' \
    --exclude '/src' \
    --exclude '.DS_Store' \
    --exclude '/.env' \
    --exclude '/data' \
    --exclude '/uploads' \
    --exclude '/backups' \
    dist package.json package-lock.json \
    "${REMOTE_HOST}:${REMOTE_DIR}/"

  if [ -d "certs/apple" ]; then
    log "Syncing Apple root certificates without touching remote private keys"
    rsync -avzc \
      -e "ssh -o StrictHostKeyChecking=no" \
      certs/apple/ \
      "${REMOTE_HOST}:${REMOTE_DIR}/certs/apple/"
  fi

  log "Installing dependencies, running migrations, and starting PM2..."
  ssh -o StrictHostKeyChecking=no "${REMOTE_HOST}" "
    cd ${REMOTE_DIR} && \
    mkdir -p data uploads backups certs/apple && \

    # Create .env if it doesn't exist
    if [ ! -f .env ]; then
      echo 'PORT=${SYNCA_PORT}' > .env
      echo 'APPLE_CLIENT_ID=org.haerth.synca' >> .env
      echo 'APNS_ENABLED=false' >> .env
      echo 'APNS_TOPIC=org.haerth.synca' >> .env
      echo '[deploy] Created default .env (APNS disabled, port ${SYNCA_PORT})'
    fi && \

    # Backup database if it exists
    DB_FILE='${REMOTE_DIR}/data/synca.sqlite' && \
    if [ -f \"\${DB_FILE}\" ]; then
      TS=\$(date +%Y%m%d_%H%M%S)
      BACKUP_FILE='${REMOTE_DIR}/backups/synca_'\${TS}'.sqlite.gz'
      gzip -c \"\${DB_FILE}\" > \"\${BACKUP_FILE}\"
      echo \"[backup] created \${BACKUP_FILE}\"
    else
      echo '[backup] skipped (first deploy, no db yet)'
    fi && \

    npm ci --production && \
    PORT=${SYNCA_PORT} node dist/src/migrate.js && \

    # Start or restart PM2
    if pm2 describe ${PM2_APP_NAME} > /dev/null 2>&1; then
      pm2 restart ${PM2_APP_NAME}
      echo '[pm2] restarted ${PM2_APP_NAME}'
    else
      PORT=${SYNCA_PORT} pm2 start dist/src/server.js --name ${PM2_APP_NAME}
      echo '[pm2] started ${PM2_APP_NAME} on port ${SYNCA_PORT}'
    fi && \
    pm2 save
  "

  log "Deployment complete! 🚀"
  log "Synca API running on port ${SYNCA_PORT}"
  log "Next: Configure nginx + SSL for synca.haerth.cn"
}

deploy
