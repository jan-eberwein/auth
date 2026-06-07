#!/bin/bash
# =============================================================================
# SNode.C IdP — Scheduled Backup Script
# Backs up SQLite DB + RSA keys to timestamped archive.
# Keeps last 14 daily backups.
# Log: /var/log/auth-idp/backup.log
# =============================================================================
set -euo pipefail

BACKUP_DIR="/opt/apps/backups/auth-idp"
LOG_DIR="/var/log/auth-idp"
LOG_FILE="$LOG_DIR/backup.log"
KEEP_DAYS=14

mkdir -p "$BACKUP_DIR" "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Auth IdP Scheduled Backup ==="

BACKUP_TS=$(date '+%Y%m%d_%H%M%S')
BACKUP_PATH="$BACKUP_DIR/backup_${BACKUP_TS}"
mkdir -p "$BACKUP_PATH"

# ── Backup DB volume ──────────────────────────────────────────────────────────
if docker volume ls -q | grep -q "auth_auth_data"; then
    docker run --rm \
        -v auth_auth_data:/data:ro \
        -v "$BACKUP_PATH":/backup \
        debian:bookworm-slim \
        sh -c "cp -r /data/* /backup/db/ 2>/dev/null; mkdir -p /backup/db && cp -r /data/. /backup/db/" \
        2>>"$LOG_FILE" && log "DB volume backed up."
else
    log "WARNING: auth_auth_data volume not found."
fi

# ── Backup keys volume ────────────────────────────────────────────────────────
if docker volume ls -q | grep -q "auth_auth_keys"; then
    docker run --rm \
        -v auth_auth_keys:/keys:ro \
        -v "$BACKUP_PATH":/backup \
        debian:bookworm-slim \
        sh -c "mkdir -p /backup/keys && cp /keys/*.pem /backup/keys/ 2>/dev/null || true" \
        2>>"$LOG_FILE" && log "Keys volume backed up."
else
    log "WARNING: auth_auth_keys volume not found."
fi

# ── Create tar archive ────────────────────────────────────────────────────────
ARCHIVE="$BACKUP_DIR/backup_${BACKUP_TS}.tar.gz"
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" "backup_${BACKUP_TS}" 2>>"$LOG_FILE" \
    && rm -rf "$BACKUP_PATH" \
    && log "Archive: $ARCHIVE ($(du -sh "$ARCHIVE" | cut -f1))"

# ── Prune old backups ─────────────────────────────────────────────────────────
DELETED=$(find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime "+${KEEP_DAYS}" -print -delete 2>>"$LOG_FILE" | wc -l)
[ "$DELETED" -gt 0 ] && log "Pruned $DELETED old backup(s) older than ${KEEP_DAYS} days."

log "=== Backup done: $ARCHIVE ==="
