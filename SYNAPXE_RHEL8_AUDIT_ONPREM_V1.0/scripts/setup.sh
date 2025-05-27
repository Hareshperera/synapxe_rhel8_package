#!/bin/bash

# Setup script for Synapxe RHEL8 Audit Package

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Set base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create necessary directories if they don't exist
mkdir -p "${BASE_DIR}/logs"
mkdir -p "${BASE_DIR}/backup"

# Set correct permissions
chmod 750 "${BASE_DIR}/bin"
chmod 750 "${BASE_DIR}/scripts"
chmod 640 "${BASE_DIR}/config/"*
chmod 750 "${BASE_DIR}/logs"
chmod 750 "${BASE_DIR}/backup"
chmod +x "${BASE_DIR}/bin/"*.sh
chmod +x "${BASE_DIR}/scripts/"*.sh

# Check required packages
REQUIRED_PACKAGES=("nftables" "firewalld")
MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! rpm -q "$pkg" >/dev/null 2>&1; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "Missing required packages: ${MISSING_PACKAGES[*]}"
    echo "Please install them using: dnf install ${MISSING_PACKAGES[*]}"
    exit 1
fi

# Check system requirements
DISK_SPACE=$(df -k "${BASE_DIR}" | awk 'NR==2 {print $4}')
TOTAL_MEM=$(free -m | awk 'NR==2 {print $2}')

if [ "$DISK_SPACE" -lt 500000 ]; then
    echo "Warning: Less than 500MB free disk space available"
fi

if [ "$TOTAL_MEM" -lt 1024 ]; then
    echo "Warning: Less than 1GB RAM available"
fi

# Create log rotation configuration
cat > /etc/logrotate.d/synapxe_audit << EOF
${BASE_DIR}/logs/*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF

echo "Setup completed successfully!"
echo "Please review configuration in ${BASE_DIR}/config/config.conf" 