#!/bin/bash

# Backup script for Synapxe RHEL8 Audit Package

# Set base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BASE_DIR}/backup"
BACKUP_FILE="${BACKUP_DIR}/synapxe_audit_backup_${TIMESTAMP}.tar.gz"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create backup archive
tar -czf "$BACKUP_FILE" \
    -C "${BASE_DIR}" \
    --exclude="backup/*" \
    --exclude="logs/*" \
    --exclude="*.tmp" \
    --exclude="*.bak" \
    .

# Set correct permissions
chmod 640 "$BACKUP_FILE"

# Clean up old backups (keep last 5)
cd "$BACKUP_DIR" && ls -t synapxe_audit_backup_*.tar.gz | tail -n +6 | xargs -r rm --

echo "Backup created: $BACKUP_FILE" 