#!/bin/bash

# Synapxe Custom CIS RHEL 8 Audit Script - Online Version

# Error handling function
handle_error() {
    local exit_code=$?
    echo "Error: $1 (Exit code: $exit_code)" >&2
    exit $exit_code
}

# Check for root privileges
[ "$(id -u)" -eq 0 ] || handle_error "This script must be run as root"

# Check internet connectivity
ping -c 1 google.com >/dev/null 2>&1 || handle_error "No internet connection available"

# Secure results directory
RESULT_DIR="/var/log/synapxe_audit"
RESULT_FILE="${RESULT_DIR}/synapxe_rhel8_audit_results.txt"

# Create secure results directory
mkdir -p "${RESULT_DIR}" || handle_error "Failed to create results directory"
chmod 750 "${RESULT_DIR}" || handle_error "Failed to set directory permissions"

# Function to install required packages
install_packages() {
    local packages=("nftables" "firewalld")
    for pkg in "${packages[@]}"; do
        rpm -q "$pkg" >/dev/null 2>&1 || {
            echo "Installing $pkg..."
            dnf install -y "$pkg" || handle_error "Failed to install $pkg"
        }
    done
}

# Install required packages
install_packages

# Check required commands
REQUIRED_COMMANDS=("rpm" "systemctl" "grep" "awk" "stat" "sysctl" "nft" "firewall-cmd")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || handle_error "Required command not found: $cmd. Please ensure all required packages are installed."
done

// ... rest of the existing code ...