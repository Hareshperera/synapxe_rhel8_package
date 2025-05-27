#!/bin/bash

# Synapxe Custom CIS RHEL 8 Audit Script - Based on Baseline 2025 by CPE Team 

# Error handling function
handle_error() {
    local exit_code=$?
    echo "Error: $1 (Exit code: $exit_code)" >&2
    exit $exit_code
}

# Enhanced error handling and recovery
trap 'cleanup' EXIT
trap 'handle_interrupt' INT TERM

cleanup() {
    local exit_code=$?
    # Clean up temporary files
    [ -f "${TEMP_FILE:-}" ] && rm -f "$TEMP_FILE"
    # Archive incomplete results if they exist
    [ -f "${RESULT_FILE:-}" ] && mv "$RESULT_FILE" "${RESULT_FILE}.incomplete"
    exit $exit_code
}

handle_interrupt() {
    echo "\nScript interrupted. Cleaning up..." >&2
    cleanup
}

handle_error() {
    local exit_code=$?
    local error_msg=$1
    local severity=${2:-"ERROR"}
    
    case $severity in
        "CRITICAL")
            echo "Critical Error: $error_msg (Exit code: $exit_code)" >&2
            cleanup
            exit $exit_code
            ;;
        "WARNING")
            echo "Warning: $error_msg" >&2
            return 1
            ;;
        "ERROR")
            echo "Error: $error_msg (Exit code: $exit_code)" >&2
            return $exit_code
            ;;
    esac
}

# Check for root privileges
[ "$(id -u)" -eq 0 ] || handle_error "This script must be run as root"

# After initial variable declarations, add hostname
HOSTNAME=$(hostname -s)
FQDN=$(hostname -f)
OS_VERSION=$(cat /etc/redhat-release 2>/dev/null || echo "OS Version not found")
KERNEL_VERSION=$(uname -r)

# Secure results directory
RESULT_DIR="/var/log/synapxe_audit"
RESULT_FILE="${RESULT_DIR}/synapxe_rhel8_audit_${HOSTNAME}_$(date +%Y%m%d_%H%M%S).txt"

# Create secure results directory
mkdir -p "${RESULT_DIR}" || handle_error "Failed to create results directory"
chmod 750 "${RESULT_DIR}" || handle_error "Failed to set directory permissions"

# Check required packages
REQUIRED_PACKAGES=("nftables" "firewalld")
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    rpm -q "$pkg" >/dev/null 2>&1 || handle_error "Required package not found: $pkg. Please install using 'dnf install $pkg'"
done

# Check required commands
REQUIRED_COMMANDS=("rpm" "systemctl" "grep" "awk" "stat" "sysctl" "nft" "firewall-cmd")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || handle_error "Required command not found: $cmd. Please ensure all required packages are installed."
done

# Initialize results file
> "$RESULT_FILE" || handle_error "Failed to create results file"

# Enhanced logging with syslog integration and JSON output
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local severity=${2:-INFO}
    local indent="    "
    local log_entry="[${timestamp}] [${severity}] ${indent}${1}"
    
    # Standard log file output
    echo "$log_entry" | tee -a "$RESULT_FILE"
    
    # Syslog integration
    logger -t "synapxe_audit" -p "local0.${severity,,}" "$1"
    
    # JSON output if enabled
    if [ "${JSON_OUTPUT:-false}" = true ]; then
        printf '{"timestamp":"%s","severity":"%s","message":"%s"}\n' \
            "$timestamp" "$severity" "$1" >> "${RESULT_FILE}.json"
    fi
    
    # Archive logs if file size exceeds limit
    if [ -f "$RESULT_FILE" ] && [ $(stat -f%z "$RESULT_FILE") -gt 5242880 ]; then # 5MB
        setup_logging
    fi
}

# Enhanced log rotation with compression
setup_logging() {
    local max_logs=5
    local compress_after=7 # days
    local compress_cmd="gzip -9"  # Maximum compression

    # Rotate existing logs
    for ((i=max_logs; i>0; i--)); do
        if [ -f "${RESULT_FILE}.$((i-1))" ]; then
            mv "${RESULT_FILE}.$((i-1))" "${RESULT_FILE}.$i"
            
            # Compress logs older than compress_after days
            if [ "$i" -gt "$compress_after" ] && [ ! -f "${RESULT_FILE}.$i.gz" ]; then
                $compress_cmd "${RESULT_FILE}.$i"
            fi
        fi
    done

    # Cleanup old compressed logs
    find "$RESULT_DIR" -name "*.gz" -mtime +30 -delete
}

log_section() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf '\n[%s] %s\n%s\n' "$timestamp" "$1" "$(printf '=%.0s' {1..80})" | tee -a "$RESULT_FILE"
}

# Enhanced summary generation
generate_summary() {
    local total_tests=$(grep -c "\[PASS\]\|\[FAIL\]" "$RESULT_FILE")
    local passed_tests=$(grep -c "\[PASS\]" "$RESULT_FILE")
    local failed_tests=$(grep -c "\[FAIL\]" "$RESULT_FILE")
    local compliance_rate=$((passed_tests * 100 / total_tests))
    
    echo "\nAUDIT SUMMARY REPORT" | tee -a "$RESULT_FILE"
    echo "$(printf '=%.0s' {1..80})" | tee -a "$RESULT_FILE"
    printf "%-20s: %d\n" "Total Tests" "$total_tests" | tee -a "$RESULT_FILE"
    printf "%-20s: %d\n" "Passed Tests" "$passed_tests" | tee -a "$RESULT_FILE"
    printf "%-20s: %d\n" "Failed Tests" "$failed_tests" | tee -a "$RESULT_FILE"
    printf "%-20s: %d%%\n" "Compliance Rate" "$compliance_rate" | tee -a "$RESULT_FILE"
    echo "\nDetailed results available in: $RESULT_FILE" | tee -a "$RESULT_FILE"

    # Generate HTML report after summary
    generate_html_report "$total_tests" "$passed_tests" "$failed_tests" "$compliance_rate"
}

# Enhanced HTML report generation with fixed output handling
generate_html_report() {
    local total_tests=$1
    local passed_tests=$2
    local failed_tests=$3
    local compliance_rate=$4
    local report_file="${RESULT_DIR}/synapxe_rhel8_audit_${HOSTNAME}_$(date +%Y%m%d_%H%M%S).html"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure directory exists
    mkdir -p "$(dirname "$report_file")" || handle_error "Failed to create HTML report directory" "ERROR"
    
    # Create HTML report with debug logging
    log "Generating HTML report at: $report_file" "INFO"
    
    # Start HTML file
    cat > "$report_file" << 'EOF' || handle_error "Failed to create HTML file" "ERROR"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Synapxe RHEL 8 Audit Report - SERVER_HOSTNAME</title>
    <style>
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            line-height: 1.6;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .header {
            background: #2c3e50;
            color: white;
            padding: 20px;
            border-radius: 8px 8px 0 0;
            margin-bottom: 20px;
        }
        .server-info {
            background: #34495e;
            color: white;
            padding: 15px;
            border-radius: 4px;
            margin: 20px 0;
        }
        .server-info table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }
        .server-info th, .server-info td {
            padding: 8px;
            text-align: left;
            border-bottom: 1px solid #456789;
        }
        .server-info th {
            color: #bdc3c7;
        }
        .summary-box {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 4px;
            padding: 15px;
            margin-bottom: 20px;
        }
        .progress-bar {
            background: #e9ecef;
            border-radius: 4px;
            height: 20px;
            margin: 10px 0;
            overflow: hidden;
        }
        .progress-fill {
            background: #28a745;
            height: 100%;
            border-radius: 4px;
            transition: width 0.5s ease-in-out;
        }
        .section {
            margin: 20px 0;
            padding: 15px;
            border: 1px solid #dee2e6;
            border-radius: 4px;
        }
        .pass { color: #28a745; }
        .fail { color: #dc3545; }
        .info { color: #17a2b8; }
        .warning { color: #ffc107; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Synapxe RHEL 8 Audit Report</h1>
            <p>Generated on: TIMESTAMP</p>
        </div>

        <div class="server-info">
            <h2>Server Information</h2>
            <table>
                <tr>
                    <th>Hostname</th>
                    <td>SERVER_HOSTNAME</td>
                </tr>
                <tr>
                    <th>FQDN</th>
                    <td>SERVER_FQDN</td>
                </tr>
                <tr>
                    <th>OS Version</th>
                    <td>OS_VERSION</td>
                </tr>
                <tr>
                    <th>Kernel Version</th>
                    <td>KERNEL_VERSION</td>
                </tr>
            </table>
        </div>
        
        <div class="summary-box">
            <h2>Executive Summary</h2>
            <div class="progress-bar">
                <div class="progress-fill" style="width: COMPLIANCE_RATE%;"></div>
            </div>
            <p>Compliance Rate: COMPLIANCE_RATE%</p>
            <table>
                <tr><th>Metric</th><th>Count</th></tr>
                <tr><td>Total Tests</td><td>TOTAL_TESTS</td></tr>
                <tr><td>Passed Tests</td><td>PASSED_TESTS</td></tr>
                <tr><td>Failed Tests</td><td>FAILED_TESTS</td></tr>
            </table>
        </div>
        <div class="results">
EOF

    # Replace placeholders with actual values
    sed -i.bak "s/SERVER_HOSTNAME/$HOSTNAME/g" "$report_file"
    sed -i.bak "s/SERVER_FQDN/$FQDN/g" "$report_file"
    sed -i.bak "s|OS_VERSION|$OS_VERSION|g" "$report_file"
    sed -i.bak "s/KERNEL_VERSION/$KERNEL_VERSION/g" "$report_file"
    sed -i.bak "s/TIMESTAMP/$timestamp/g" "$report_file"
    sed -i.bak "s/COMPLIANCE_RATE/$compliance_rate/g" "$report_file"
    sed -i.bak "s/TOTAL_TESTS/$total_tests/g" "$report_file"
    sed -i.bak "s/PASSED_TESTS/$passed_tests/g" "$report_file"
    sed -i.bak "s/FAILED_TESTS/$failed_tests/g" "$report_file"
    
    # Add test results
    while IFS= read -r line; do
        if [[ $line == *"[PASS]"* ]]; then
            echo "<p class=\"pass\">$line</p>" >> "$report_file"
        elif [[ $line == *"[FAIL]"* ]]; then
            echo "<p class=\"fail\">$line</p>" >> "$report_file"
        elif [[ $line == *"[INFO]"* ]]; then
            echo "<p class=\"info\">$line</p>" >> "$report_file"
        elif [[ $line == *"[WARNING]"* ]]; then
            echo "<p class=\"warning\">$line</p>" >> "$report_file"
        elif [[ $line == *"="* ]]; then
            echo "<h3>$line</h3>" >> "$report_file"
        else
            echo "<p>$line</p>" >> "$report_file"
        fi
    done < "$RESULT_FILE"

    # Close HTML document
    cat >> "$report_file" << 'EOF'
        </div>
    </div>
</body>
</html>
EOF

    # Set proper permissions and check if file was created
    if [ -f "$report_file" ]; then
        chmod 644 "$report_file"
        log "HTML report successfully generated: $report_file" "INFO"
    else
        handle_error "Failed to verify HTML report creation" "ERROR"
    fi
    
    # Clean up backup files from sed
    rm -f "${report_file}.bak"
}

log_section "1.1.1.x - Kernel Module Checks"
modules=(cramfs freevxfs hfs hfsplus jffs2 squashfs udf usb-storage)
for mod in "${modules[@]}"; do
    log "Checking module: $mod"
    lsmod | grep -q "^$mod" && log " - [FAIL] $mod is loaded" || log " - [PASS] $mod is not loaded"
    grep -Rq "install $mod /bin/false" /etc/modprobe.d && log " - [PASS] install $mod /bin/false exists" || log " - [FAIL] install $mod /bin/false not found"
    grep -Rq "blacklist $mod" /etc/modprobe.d && log " - [PASS] blacklist $mod exists" || log " - [FAIL] blacklist $mod not found"
done

log_section "1.1.2.x - Partition Mount Options"
/bin/mount | grep -q "on /tmp " && log " - [PASS] /tmp is mounted" || log " - [FAIL] /tmp is not mounted"
findmnt -n /tmp | grep -q "nodev" && log " - [PASS] nodev set on /tmp" || log " - [FAIL] nodev not set on /tmp"

log_section "1.1.3.x - /var/tmp Mount Options"
/bin/mount | grep -q "on /var/tmp " && log " - [PASS] /var/tmp is mounted" || log " - [FAIL] /var/tmp is not mounted"
findmnt -n /var/tmp | grep -q "nodev" && log " - [PASS] nodev set on /var/tmp" || log " - [FAIL] nodev not set on /var/tmp"
findmnt -n /var/tmp | grep -q "nosuid" && log " - [PASS] nosuid set on /var/tmp" || log " - [FAIL] nosuid not set on /var/tmp"
findmnt -n /var/tmp | grep -q "noexec" && log " - [PASS] noexec set on /var/tmp" || log " - [FAIL] noexec not set on /var/tmp"

log_section "1.1.4.x - /var Mount Options"
/bin/mount | grep -q "on /var " && log " - [PASS] /var is mounted" || log " - [FAIL] /var is not mounted"

log_section "1.1.5.x - /var/log Mount Options"
/bin/mount | grep -q "on /var/log " && log " - [PASS] /var/log is mounted" || log " - [FAIL] /var/log is not mounted"

log_section "1.1.6.x - /var/log/audit Mount Options"
/bin/mount | grep -q "on /var/log/audit " && log " - [PASS] /var/log/audit is mounted" || log " - [FAIL] /var/log/audit is not mounted"

log_section "1.1.7.x - /home Mount Options"
/bin/mount | grep -q "on /home " && log " - [PASS] /home is mounted" || log " - [FAIL] /home is not mounted"
findmnt -n /home | grep -q "nodev" && log " - [PASS] nodev set on /home" || log " - [FAIL] nodev not set on /home"

log_section "1.1.8.x - /dev/shm Mount Options"
/bin/mount | grep -q "on /dev/shm " && log " - [PASS] /dev/shm is mounted" || log " - [FAIL] /dev/shm is not mounted"
findmnt -n /dev/shm | grep -q "nodev" && log " - [PASS] nodev set on /dev/shm" || log " - [FAIL] nodev not set on /dev/shm"
findmnt -n /dev/shm | grep -q "nosuid" && log " - [PASS] nosuid set on /dev/shm" || log " - [FAIL] nosuid not set on /dev/shm"
findmnt -n /dev/shm | grep -q "noexec" && log " - [PASS] noexec set on /dev/shm" || log " - [FAIL] noexec not set on /dev/shm"

log_section "1.1.9.x - Sticky bit on world-writable dirs"
for dir in $(find / -xdev -type d -perm -0002 2>/dev/null); do
    if [ -d "$dir" ]; then
        ls -ld "$dir" | grep -q 't' && log " - [PASS] Sticky bit set on $dir" || log " - [FAIL] Sticky bit not set on $dir"
    fi
done

log_section "1.2 - Bootloader Configuration"
grep -E "^set superusers" /boot/grub2/user.cfg && log " - [PASS] GRUB superuser is set" || log " - [FAIL] GRUB superuser not set"
grep -E "^password_pbkdf2" /boot/grub2/user.cfg && log " - [PASS] GRUB password is set" || log " - [FAIL] GRUB password not set"
[ -f /boot/grub2/grub.cfg ] && stat -c "%a %U %G" /boot/grub2/grub.cfg | grep -q "400 root root" && log " - [PASS] grub.cfg has secure permissions" || log " - [FAIL] grub.cfg permissions not secure"

log_section "1.3 - SELinux Configuration"
getenforce | grep -q "Enforcing" && log " - [PASS] SELinux is enforcing" || log " - [FAIL] SELinux is not enforcing"
grep -q "^SELINUX=enforcing" /etc/selinux/config && log " - [PASS] SELINUX=enforcing in config" || log " - [FAIL] SELINUX not enforcing in config"
rpm -q setroubleshoot >/dev/null && log " - [FAIL] setroubleshoot is installed" || log " - [PASS] setroubleshoot is not installed"
rpm -q mcstrans >/dev/null && log " - [FAIL] mcstrans is installed" || log " - [PASS] mcstrans is not installed"

log_section "1.4 - File Permissions (bootloader)"
[ -f /boot/grub2/grub.cfg ] && stat -c "%a" /boot/grub2/grub.cfg | grep -q "400" && log " - [PASS] grub.cfg is 400" || log " - [FAIL] grub.cfg not 400"
stat -c "%U %G" /boot/grub2/grub.cfg | grep -q "root root" && log " - [PASS] grub.cfg owned by root" || log " - [FAIL] grub.cfg not owned by root"

log_section "1.5 - Additional Process Hardening"
sysctl kernel.dmesg_restrict | grep -q "1" && log " - [PASS] dmesg_restrict enabled" || log " - [FAIL] dmesg_restrict not enabled"
sysctl fs.protected_hardlinks | grep -q "1" && log " - [PASS] protected_hardlinks enabled" || log " - [FAIL] protected_hardlinks not enabled"
sysctl fs.protected_symlinks | grep -q "1" && log " - [PASS] protected_symlinks enabled" || log " - [FAIL] protected_symlinks not enabled"
sysctl kernel.kptr_restrict | grep -q "1" && log " - [PASS] kptr_restrict enabled" || log " - [FAIL] kptr_restrict not enabled"

log_section "1.6 - Crypto Policy"
grep -q "DEFAULT" /etc/crypto-policies/config && log " - [PASS] DEFAULT crypto policy in use" || log " - [WARN] DEFAULT crypto policy not in use"

# Check SHA1 hash and signature support
update-crypto-policies --show | grep -q "SHA1:" && log " - [FAIL] SHA1 hash is enabled" || log " - [PASS] SHA1 hash is disabled"

# Check CBC for SSH
update-crypto-policies --show | grep -q "CBC:" && log " - [FAIL] CBC ciphers are enabled" || log " - [PASS] CBC ciphers are disabled"

# Check MACs less than 128 bits
update-crypto-policies --show | grep -q "MAC-<128:" && log " - [FAIL] MACs less than 128 bits are enabled" || log " - [PASS] MACs less than 128 bits are disabled"

log_section "1.7 - Warning Banners"
[ -f /etc/issue ] && grep -qi "authorized" /etc/issue && log " - [PASS] /etc/issue contains warning" || log " - [FAIL] /etc/issue missing warning"
[ -f /etc/issue.net ] && grep -qi "authorized" /etc/issue.net && log " - [PASS] /etc/issue.net contains warning" || log " - [FAIL] /etc/issue.net missing warning"
[ -f /etc/motd ] && stat -c "%a" /etc/motd | grep -q "644" && log " - [PASS] /etc/motd has 644 permissions" || log " - [FAIL] /etc/motd does not have 644 permissions"

log_section "1.8 - GNOME Display Manager"
if rpm -q gdm > /dev/null; then
    log " - [INFO] GNOME is installed"
    
    # Check screen lock settings
    if [ -f "/etc/dconf/db/local.d/00-screensaver" ]; then
        grep -q "idle-delay=uint32 900" /etc/dconf/db/local.d/00-screensaver && \
            log " - [PASS] Screen lock timeout configured" || \
            log " - [FAIL] Screen lock timeout not configured"
        
        grep -q "lock-enabled=true" /etc/dconf/db/local.d/00-screensaver && \
            log " - [PASS] Screen lock enabled" || \
            log " - [FAIL] Screen lock not enabled"
    else
        log " - [FAIL] Screen lock configuration file missing"
    fi
    
    # Check automount settings
    if [ -f "/etc/dconf/db/local.d/00-media-automount" ]; then
        grep -q "automount=false" /etc/dconf/db/local.d/00-media-automount && \
            log " - [PASS] Automount disabled" || \
            log " - [FAIL] Automount enabled"
            
        grep -q "automount-open=false" /etc/dconf/db/local.d/00-media-automount && \
            log " - [PASS] Automount-open disabled" || \
            log " - [FAIL] Automount-open enabled"
    else
        log " - [FAIL] Media automount configuration file missing"
    fi
    
    # Check autorun settings
    if [ -f "/etc/dconf/db/local.d/00-autorun" ]; then
        grep -q "autorun-never=true" /etc/dconf/db/local.d/00-autorun && \
            log " - [PASS] Autorun disabled" || \
            log " - [FAIL] Autorun enabled"
    else
        log " - [FAIL] Autorun configuration file missing"
    fi
else
    log " - [PASS] GNOME is not installed"
fi

log "\nChapter 1 complete. Results saved in $RESULT_FILE"

log_section "Chapter 2 - Services"

# 2.1 Ensure xinetd is not installed
rpm -q xinetd > /dev/null && log " - [FAIL] xinetd is installed" || log " - [PASS] xinetd is not installed"

# 2.2 Ensure chronyd is configured
if rpm -q chrony > /dev/null; then
    log " - [PASS] chrony is installed"
    systemctl is-enabled chronyd | grep -q enabled && log " - [PASS] chronyd is enabled" || log " - [FAIL] chronyd is not enabled"
    systemctl is-active chronyd | grep -q active && log " - [PASS] chronyd is active" || log " - [FAIL] chronyd is not active"
else
    log " - [FAIL] chrony is not installed"
fi

# 2.2.1 Ensure ntp is not installed if chronyd is used
rpm -q ntp > /dev/null && log " - [FAIL] ntp is installed (should use chrony)" || log " - [PASS] ntp is not installed"

# 2.3 Remove unnecessary services
unused_services=(avahi cups dhcpd slapd nfs-server bind vsftpd httpd dovecot smb rpcbind squid snmpd telnet tftp rsync ypserv)
for svc in "${unused_services[@]}"; do
    if rpm -q $svc > /dev/null; then
        log " - [FAIL] $svc is installed"
    else
        log " - [PASS] $svc is not installed"
    fi
done

# 2.4 Remove X Windows if not needed
rpm -q xorg-x11-server-common > /dev/null && log " - [INFO] X11 is installed" || log " - [PASS] X11 is not installed"

# 2.5 Disable Ctrl+Alt+Del
systemctl status ctrl-alt-del.target | grep -q "masked" && log " - [PASS] Ctrl+Alt+Del is disabled" || log " - [FAIL] Ctrl+Alt+Del is not disabled"

log "\nChapter 2 audit complete. Results appended to $RESULT_FILE"

log_section "Chapter 3 - Network Configuration"

# 3.1 Ensure IP forwarding is disabled
sysctl net.ipv4.ip_forward | grep -q "0" && log " - [PASS] net.ipv4.ip_forward is 0" || log " - [FAIL] net.ipv4.ip_forward is not 0"
sysctl net.ipv6.conf.all.forwarding | grep -q "0" && log " - [PASS] net.ipv6.conf.all.forwarding is 0" || log " - [FAIL] net.ipv6.conf.all.forwarding is not 0"

# 3.2 Ensure packet redirect sending is disabled
for intf in all default; do
    sysctl net.ipv4.conf.$intf.send_redirects | grep -q "0" && log " - [PASS] send_redirects ($intf) is 0" || log " - [FAIL] send_redirects ($intf) is not 0"
done

# 3.3 Ensure source routed packets are not accepted
for intf in all default; do
    sysctl net.ipv4.conf.$intf.accept_source_route | grep -q "0" && log " - [PASS] source_route ($intf) is 0" || log " - [FAIL] source_route ($intf) is not 0"
    sysctl net.ipv6.conf.$intf.accept_source_route | grep -q "0" && log " - [PASS] source_route IPv6 ($intf) is 0" || log " - [FAIL] source_route IPv6 ($intf) is not 0"
done

# 3.4 Ensure ICMP redirects are not accepted
for intf in all default; do
    sysctl net.ipv4.conf.$intf.accept_redirects | grep -q "0" && log " - [PASS] accept_redirects ($intf) is 0" || log " - [FAIL] accept_redirects ($intf) is not 0"
    sysctl net.ipv6.conf.$intf.accept_redirects | grep -q "0" && log " - [PASS] accept_redirects IPv6 ($intf) is 0" || log " - [FAIL] accept_redirects IPv6 ($intf) is not 0"
done

# 3.5 Ensure secure ICMP redirects are not accepted
for intf in all default; do
    sysctl net.ipv4.conf.$intf.secure_redirects | grep -q "0" && log " - [PASS] secure_redirects ($intf) is 0" || log " - [FAIL] secure_redirects ($intf) is not 0"
done

# 3.6 Ensure suspicious packets are logged
sysctl net.ipv4.conf.all.log_martians | grep -q "1" && log " - [PASS] log_martians is 1" || log " - [FAIL] log_martians is not 1"

# 3.7 Ensure broadcast ICMP requests are ignored
sysctl net.ipv4.icmp_echo_ignore_broadcasts | grep -q "1" && log " - [PASS] icmp_echo_ignore_broadcasts is 1" || log " - [FAIL] icmp_echo_ignore_broadcasts is not 1"

# 3.8 Ensure bogus ICMP responses are ignored
sysctl net.ipv4.icmp_ignore_bogus_error_responses | grep -q "1" && log " - [PASS] icmp_ignore_bogus_error_responses is 1" || log " - [FAIL] icmp_ignore_bogus_error_responses is not 1"

# 3.9 Ensure reverse path filtering is enabled
for intf in all default; do
    sysctl net.ipv4.conf.$intf.rp_filter | grep -q "1" && log " - [PASS] rp_filter ($intf) is 1" || log " - [FAIL] rp_filter ($intf) is not 1"
done

# 3.10 Ensure TCP SYN Cookies is enabled
sysctl net.ipv4.tcp_syncookies | grep -q "1" && log " - [PASS] tcp_syncookies is 1" || log " - [FAIL] tcp_syncookies is not 1"

log "\nChapter 3 audit complete. Results appended to $RESULT_FILE"

log_section "Chapter 4 - Host-Based Firewall"

# 4.1 Ensure a firewall package is installed
if rpm -q nftables > /dev/null; then
    log " - [PASS] nftables is installed"
elif rpm -q firewalld > /dev/null; then
    log " - [PASS] firewalld is installed"
else
    log " - [FAIL] No supported firewall package is installed"
fi

# 4.2.1 Ensure nftables is enabled and running
if systemctl is-enabled nftables &>/dev/null && systemctl is-active nftables &>/dev/null; then
    log " - [PASS] nftables is enabled and running"
else
    log " - [INFO] nftables not enabled/running (may use firewalld instead)"
fi

# 4.2.2 Ensure nftables default deny policy
nft list ruleset | grep -q "hook input.*type filter.*policy drop" && log " - [PASS] nftables input default policy is drop" || log " - [FAIL] nftables input default policy is not drop"
nft list ruleset | grep -q "hook forward.*type filter.*policy drop" && log " - [PASS] nftables forward default policy is drop" || log " - [FAIL] nftables forward default policy is not drop"
nft list ruleset | grep -q "hook output.*type filter.*policy drop" && log " - [PASS] nftables output default policy is drop" || log " - [FAIL] nftables output default policy is not drop"

# 4.2.3 Ensure nftables rules exist
nft list ruleset | grep -q "inet filter" && log " - [PASS] nftables filter table exists" || log " - [FAIL] nftables filter table missing"

# 4.3.1 Ensure firewalld is enabled and running (alternative)
if systemctl is-enabled firewalld &>/dev/null && systemctl is-active firewalld &>/dev/null; then
    log " - [PASS] firewalld is enabled and running"
else
    log " - [INFO] firewalld not enabled/running (may use nftables instead)"
fi

# 4.3.2 Ensure firewalld default zone is set to drop or block
zone=$(firewall-cmd --get-default-zone 2>/dev/null)
if [[ "$zone" == "block" || "$zone" == "drop" ]]; then
    log " - [PASS] firewalld default zone is $zone"
else
    log " - [FAIL] firewalld default zone is $zone (should be drop or block)"
fi

log "\nChapter 4 audit complete. Results appended to $RESULT_FILE"

log_section "Chapter 5 - Access, Authentication, and Authorization"

# 5.1 - SSH Server Configuration
sshd_config="/etc/ssh/sshd_config"

# Add at the beginning of the script
CONFIG_FILE="/etc/synapxe_audit/config.conf"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        log "Warning: Config file not found, using defaults"
    fi
}

# Add after error handling function
recover_and_continue() {
    local error_msg=$1
    log "WARNING: $error_msg - continuing with next test"
    return 0
}

# Add before test sections
SKIP_TESTS=()

should_skip_test() {
    local test_name=$1
    [[ " ${SKIP_TESTS[@]} " =~ " $test_name " ]] && return 0 || return 1
}

# Example usage in a test
check_sshd_option() {
    local opt=$1
    local val=$2
    if [ ! -f "$sshd_config" ]; then
        recover_and_continue "SSH config file not found"
        return
    fi
    grep -Ei "^\s*$opt\s+$val" "$sshd_config" > /dev/null && \
        log " - [PASS] $opt is set to $val" || \
        log " - [FAIL] $opt is not set to $val"
}

check_sshd_option "PermitRootLogin" "no"
check_sshd_option "Protocol" "2"
check_sshd_option "MaxAuthTries" "4"
check_sshd_option "IgnoreRhosts" "yes"
check_sshd_option "HostbasedAuthentication" "no"
check_sshd_option "PermitEmptyPasswords" "no"
check_sshd_option "LoginGraceTime" "60"
check_sshd_option "ClientAliveInterval" "300"
check_sshd_option "ClientAliveCountMax" "3"
check_sshd_option "UsePAM" "yes"

# 5.2 - Sudo Configuration
[ -f /etc/sudoers ] && log " - [PASS] /etc/sudoers exists" || log " - [FAIL] /etc/sudoers is missing"
grep -Eq '^Defaults\s+use_pty' /etc/sudoers && log " - [PASS] sudo uses pty" || log " - [FAIL] sudo does not use pty"
grep -Eq '^Defaults\s+(log_input|log_output)' /etc/sudoers && log " - [PASS] sudo logs I/O" || log " - [FAIL] sudo does not log I/O"

# 5.3 - PAM Configuration
grep -E '^password\s+sufficient\s+pam_unix.so.*remember=' /etc/pam.d/system-auth && log " - [PASS] PAM password history enforced" || log " - [FAIL] PAM password history not enforced"

# 5.4 - User Account Policies
grep -E '^PASS_MAX_DAYS\s+90' /etc/login.defs && log " - [PASS] PASS_MAX_DAYS is 90" || log " - [FAIL] PASS_MAX_DAYS not 90"
grep -E '^PASS_MIN_DAYS\s+7' /etc/login.defs && log " - [PASS] PASS_MIN_DAYS is 7" || log " - [FAIL] PASS_MIN_DAYS not 7"
grep -E '^PASS_WARN_AGE\s+7' /etc/login.defs && log " - [PASS] PASS_WARN_AGE is 7" || log " - [FAIL] PASS_WARN_AGE not 7"

# 5.5 - Root and Admin Restrictions
grep '^root:' /etc/passwd | cut -f7 -d: | grep -q "/bin/bash" && log " - [PASS] root has valid shell" || log " - [FAIL] root shell misconfigured"
awk -F: '($3 == 0) { print $1 }' /etc/passwd | grep -q '^root$' && log " - [PASS] Only root has UID 0" || log " - [FAIL] Multiple users have UID 0"

# Enhanced SSH configuration checks
check_ssh_ciphers() {
    local allowed_ciphers="aes256-ctr,aes192-ctr,aes128-ctr"
    local allowed_macs="hmac-sha2-512,hmac-sha2-256"
    local allowed_kex="ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group14-sha256"
    
    # Check Ciphers
    if grep -q "^Ciphers" "$sshd_config"; then
        local configured_ciphers=$(grep "^Ciphers" "$sshd_config" | cut -d' ' -f2-)
        if [[ "$configured_ciphers" == "$allowed_ciphers" ]]; then
            log " - [PASS] SSH Ciphers properly configured"
        else
            log " - [FAIL] SSH Ciphers misconfigured (found: $configured_ciphers)"
        fi
    else
        log " - [FAIL] SSH Ciphers not explicitly configured"
    fi
    
    # Check MACs
    if grep -q "^MACs" "$sshd_config"; then
        local configured_macs=$(grep "^MACs" "$sshd_config" | cut -d' ' -f2-)
        if [[ "$configured_macs" == "$allowed_macs" ]]; then
            log " - [PASS] SSH MACs properly configured"
        else
            log " - [FAIL] SSH MACs misconfigured (found: $configured_macs)"
        fi
    else
        log " - [FAIL] SSH MACs not explicitly configured"
    fi
    
    # Check KexAlgorithms
    if grep -q "^KexAlgorithms" "$sshd_config"; then
        local configured_kex=$(grep "^KexAlgorithms" "$sshd_config" | cut -d' ' -f2-)
        if [[ "$configured_kex" == "$allowed_kex" ]]; then
            log " - [PASS] SSH KexAlgorithms properly configured"
        else
            log " - [FAIL] SSH KexAlgorithms misconfigured (found: $configured_kex)"
        fi
    else
        log " - [FAIL] SSH KexAlgorithms not explicitly configured"
    fi
}

# Call the enhanced SSH checks
check_ssh_ciphers

log "\nChapter 5 audit complete. Results appended to $RESULT_FILE"

log_section "Chapter 6 - Logging and Auditing"

# 6.1.1 Ensure AIDE is installed
rpm -q aide > /dev/null && log " - [PASS] AIDE is installed" || log " - [FAIL] AIDE is not installed"

# 6.1.2 Ensure AIDE is configured
[ -f /etc/aide.conf ] && log " - [PASS] /etc/aide.conf exists" || log " - [FAIL] /etc/aide.conf is missing"

# 6.1.3 Ensure AIDE is scheduled
systemctl list-timers aidecheck.timer | grep -q aidecheck && log " - [PASS] aidecheck.timer is scheduled" || log " - [FAIL] aidecheck.timer not found"

# 6.2.1 Ensure log directory permissions
stat -c "%a %U %G" /var/log | grep -q "750 root root" && log " - [PASS] /var/log permissions are 750 root root" || log " - [INFO] /var/log permissions differ"

# 6.2.2 Ensure syslog package is installed
if rpm -q rsyslog > /dev/null; then
    log " - [PASS] rsyslog is installed"
elif rpm -q syslog-ng > /dev/null; then
    log " - [PASS] syslog-ng is installed"
else
    log " - [FAIL] No syslog package installed"
fi

# 6.2.3 Ensure syslog is enabled and active
systemctl is-enabled rsyslog &>/dev/null && systemctl is-active rsyslog &>/dev/null && log " - [PASS] rsyslog enabled and running" || log " - [INFO] rsyslog not enabled/active"
systemctl is-enabled syslog-ng &>/dev/null && systemctl is-active syslog-ng &>/dev/null && log " - [PASS] syslog-ng enabled and running" || log " - [INFO] syslog-ng not enabled/active"

# 6.2.4 Ensure rsyslog default file permissions
grep -Eq '^\$FileCreateMode\s+0640' /etc/rsyslog.conf && log " - [PASS] rsyslog default file mode is 0640" || log " - [FAIL] rsyslog default file mode not 0640"

# 6.3.1 Ensure auditd is installed
rpm -q audit > /dev/null && log " - [PASS] auditd is installed" || log " - [FAIL] auditd is not installed"

# 6.3.2 Ensure auditd is enabled and active
systemctl is-enabled auditd | grep -q enabled && log " - [PASS] auditd is enabled" || log " - [FAIL] auditd is not enabled"
systemctl is-active auditd | grep -q active && log " - [PASS] auditd is running" || log " - [FAIL] auditd is not running"

# 6.3.3 Ensure auditd is protected
systemctl cat auditd | grep -q "ProtectSystem=full" && log " - [PASS] auditd has ProtectSystem=full" || log " - [FAIL] auditd missing ProtectSystem=full"

log "\nChapter 6 audit complete. Results appended to $RESULT_FILE"

log_section "Chapter 7 - System Maintenance"

# 7.1.1 Ensure permissions on /etc/passwd are configured
stat -c "%a" /etc/passwd | grep -qE "644" && log " - [PASS] /etc/passwd is 644" || log " - [FAIL] /etc/passwd is not 644"

# 7.1.2 Ensure permissions on /etc/shadow are configured
stat -c "%a" /etc/shadow | grep -qE "0" && log " - [PASS] /etc/shadow is 000" || log " - [FAIL] /etc/shadow is not 000"

# 7.1.3 Ensure permissions on /etc/group are configured
stat -c "%a" /etc/group | grep -qE "644" && log " - [PASS] /etc/group is 644" || log " - [FAIL] /etc/group is not 644"

# 7.1.4 Ensure permissions on /etc/gshadow are configured
stat -c "%a" /etc/gshadow | grep -qE "0" && log " - [PASS] /etc/gshadow is 000" || log " - [FAIL] /etc/gshadow is not 000"

# 7.1.5 Ensure root is the only UID 0 account
uid0=$(awk -F: '($3 == 0) { print $1 }' /etc/passwd)
[[ "$uid0" == "root" ]] && log " - [PASS] Only root has UID 0" || log " - [FAIL] Additional UID 0 users found: $uid0"

# 7.2.1 Ensure no legacy '+' entries exist in /etc/passwd
! grep -q '^+' /etc/passwd && log " - [PASS] No legacy '+' in /etc/passwd" || log " - [FAIL] Legacy '+' entry in /etc/passwd"

# 7.2.2 Ensure no legacy '+' entries exist in /etc/shadow
! grep -q '^+' /etc/shadow && log " - [PASS] No legacy '+' in /etc/shadow" || log " - [FAIL] Legacy '+' entry in /etc/shadow"

# 7.2.3 Ensure no legacy '+' entries exist in /etc/group
! grep -q '^+' /etc/group && log " - [PASS] No legacy '+' in /etc/group" || log " - [FAIL] Legacy '+' entry in /etc/group"

# 7.2.4 Ensure shadow group is empty
! grep ^shadow /etc/group | cut -d: -f4 | grep -vq '^$' && log " - [PASS] Shadow group is empty" || log " - [FAIL] Shadow group is not empty"

log "\nChapter 7 audit complete. Final results saved to $RESULT_FILE"

log "Audit completed. Results saved in $RESULT_FILE"

# Add after the log() function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -j, --json     Output results in JSON format"
    echo "  -q, --quiet    Suppress progress output"
    echo "  -h, --help     Show this help message"
}

# Parse command line arguments
JSON_OUTPUT=false
QUIET_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -j|--json) JSON_OUTPUT=true ;;
        -q|--quiet) QUIET_MODE=true ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done
show_progress() {
    local current=$1
    local total=$2
    local percentage=$((current * 100 / total))
    printf "\rProgress: [%-50s] %d%%" "$(printf "#%.0s" $(seq 1 $((percentage/2))))" "$percentage"
}

log_json() {
    local test_name=$1
    local result=$2
    local details=$3
    printf '{"test": "%s", "result": "%s", "details": "%s"}\n' "$test_name" "$result" "$details" >> "${RESULT_FILE}.json"
}

generate_summary() {
    local total_tests=$(grep -c "\[PASS\]\|\[FAIL\]" "$RESULT_FILE")
    local passed_tests=$(grep -c "\[PASS\]" "$RESULT_FILE")
    local failed_tests=$(grep -c "\[FAIL\]" "$RESULT_FILE")
    
    echo "\nAudit Summary:" | tee -a "$RESULT_FILE"
    echo "Total Tests: $total_tests" | tee -a "$RESULT_FILE"
    echo "Passed: $passed_tests" | tee -a "$RESULT_FILE"
    echo "Failed: $failed_tests" | tee -a "$RESULT_FILE"
    echo "Compliance Rate: $((passed_tests * 100 / total_tests))%" | tee -a "$RESULT_FILE"
}

# Add after the initial variable declarations
PARALLEL_JOBS=4  # Adjust based on system capabilities

# Performance optimizations
PARALLEL_JOBS=4
CACHE_DIR="${RESULT_DIR}/cache"

run_parallel_checks() {
    local checks=($@)
    local pids=()
    
    mkdir -p "$CACHE_DIR"
    
    # Run checks in parallel
    for ((i=0; i<${#checks[@]}; i+=PARALLEL_JOBS)); do
        for ((j=i; j<i+PARALLEL_JOBS && j<${#checks[@]}; j++)); do
            ${checks[j]} > "${CACHE_DIR}/check_${j}.tmp" & pids+=($!)
        done
        wait ${pids[@]}
    done
    
    # Collect results
    for ((i=0; i<${#checks[@]}; i++)); do
        cat "${CACHE_DIR}/check_${i}.tmp"
        rm "${CACHE_DIR}/check_${i}.tmp"
    done
}

# Add after the log functions
log_test() {
    local test_name=$1
    local result=$2
    local severity=$3  # HIGH, MEDIUM, LOW
    local details=$4
    
    printf '[%s] [%s] [%s] %s - %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$severity" \
        "$result" \
        "$test_name" \
        "$details" | tee -a "$RESULT_FILE"
}

# Add after initial setup
monitor_resources() {
    local pid=$1
    while ps -p $pid > /dev/null; do
        ps -o pid,ppid,%cpu,%mem,cmd -p $pid 2>/dev/null >> "${RESULT_FILE}.resources"
        sleep 5
    done
}

# Start monitoring
monitor_resources $$ &
MONITOR_PID=$!

# Add test metadata structure
declare -A TEST_METADATA
TEST_METADATA=(
    ["kernel_module_check"]="severity=HIGH category=SYSTEM_HARDENING"
    ["partition_mount_check"]="severity=MEDIUM category=FILESYSTEM"
    # Add more test metadata
)

# Enhanced test function
run_test() {
    local test_name=$1
    local test_cmd=$2
    local metadata=${TEST_METADATA[$test_name]}
    local severity=$(echo $metadata | grep -o 'severity=[^ ]*' | cut -d= -f2)
    local category=$(echo $metadata | grep -o 'category=[^ ]*' | cut -d= -f2)
    
    local start_time=$(date +%s)
    eval "$test_cmd"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_test "$test_name" "$?" "$severity" "$category" "$duration"
}

# Add dependency tracking
declare -A TEST_DEPENDENCIES
TEST_DEPENDENCIES=(
    ["firewall_check"]="network_enabled system_running"
    ["ssh_config_check"]="sshd_installed sshd_running"
)

check_dependencies() {
    local test_name=$1
    local deps=${TEST_DEPENDENCIES[$test_name]}
    
    for dep in $deps; do
        if ! run_test "$dep"; then
            log "Skipping $test_name due to failed dependency: $dep"
            return 1
        fi
    done
    return 0
}

# Add trend analysis
generate_trend_report() {
    local current_results=$1
    local history_dir="${RESULT_DIR}/history"
    mkdir -p "$history_dir"
    
    # Save current results with timestamp
    cp "$current_results" "$history_dir/$(date +%Y%m%d_%H%M%S).txt"
    
    # Generate trend analysis
    echo "Trend Analysis:" > "${RESULT_DIR}/trend_report.txt"
    for result in "$history_dir"/*; do
        local date=$(basename "$result" .txt)
        local pass_count=$(grep -c "\[PASS\]" "$result")
        local fail_count=$(grep -c "\[FAIL\]" "$result")
        echo "$date: Pass=$pass_count Fail=$fail_count" >> "${RESULT_DIR}/trend_report.txt"
    done
}

# Add caching for expensive operations
declare -A CACHE

cached_command() {
    local cmd=$1
    local cache_key=$(echo "$cmd" | md5sum | cut -d' ' -f1)
    
    if [[ -z ${CACHE[$cache_key]} ]]; then
        CACHE[$cache_key]=$(eval "$cmd")
    fi
    echo "${CACHE[$cache_key]}"
}

# Example usage
sysctl_value() {
    cached_command "sysctl -n $1"
}

# Add checkpoint and recovery
save_checkpoint() {
    local checkpoint_file="${RESULT_DIR}/checkpoint.txt"
    echo "LAST_COMPLETED_TEST=$1" > "$checkpoint_file"
    cp "$RESULT_FILE" "${RESULT_FILE}.checkpoint"
}

restore_from_checkpoint() {
    local checkpoint_file="${RESULT_DIR}/checkpoint.txt"
    if [[ -f "$checkpoint_file" ]]; then
        source "$checkpoint_file"
        cp "${RESULT_FILE}.checkpoint" "$RESULT_FILE"
        return 0
    fi
    return 1
}

# Enhanced security features
generate_report_signature() {
    local report_file=$1
    local signature_file="${report_file}.sig"
    
    # Generate SHA256 checksum
    sha256sum "$report_file" > "${report_file}.sha256"
    
    # Create audit trail
    cat >> "${RESULT_DIR}/audit_trail.log" << EOF
Report Generated: $(date '+%Y-%m-%d %H:%M:%S')
Executed by: $(whoami)
Hostname: $(hostname)
Checksum: $(cat "${report_file}.sha256")
EOF
}

# Enhanced reporting
generate_executive_summary() {
    local report_file=$1
    
    # Calculate trends if historical data exists
    local trend_data=""
    if [ -f "${RESULT_DIR}/historical_data.json" ]; then
        trend_data=$(calculate_trends)
    fi
    
    # Generate remediation suggestions
    local remediation_data=$(generate_remediation_suggestions)
    
    # Create executive summary
    cat > "${report_file}.summary" << EOF
Executive Summary
================

Overall Compliance: ${compliance_rate}%
Trend Analysis: ${trend_data}

Key Findings:
${remediation_data}
EOF
}

# Enhanced compatibility checks
check_compatibility() {
    # Check RHEL version
    local rhel_version=$(rpm -q --queryformat '%{VERSION}' redhat-release)
    if [[ ! "$rhel_version" =~ ^8\. ]]; then
        handle_error "This script requires RHEL 8.x (found version $rhel_version)" "CRITICAL"
    fi
    
    # Check shell environment
    if [ -z "$BASH_VERSION" ]; then
        handle_error "This script requires bash shell" "CRITICAL"
    fi
    
    # Check for virtualization
    if systemctl status 2>/dev/null | grep -q 'virtualization'; then
        log "Running in virtualized environment" "INFO"
    fi
}

# Enhanced testing framework
run_self_test() {
    local test_dir="${RESULT_DIR}/tests"
    mkdir -p "$test_dir"
    
    # Test cases
    local tests=(
        test_file_permissions
        test_logging
        test_error_handling
        test_report_generation
    )
    
    log "Starting self-test" "INFO"
    for test in "${tests[@]}"; do
        if $test; then
            log "Test passed: $test" "PASS"
        else
            log "Test failed: $test" "FAIL"
        fi
    done
}
# Version control and maintenance
VERSION="1.0.0"
LAST_UPDATE="2024-01-20"
CHANGELOG_FILE="${RESULT_DIR}/changelog.md"

show_version() {
    cat << EOF
Synapxe RHEL 8 Audit Script v${VERSION}
Last Updated: ${LAST_UPDATE}

Changelog:
$(cat "$CHANGELOG_FILE" 2>/dev/null || echo "No changelog available")
EOF
}

# Update changelog
update_changelog() {
    local version=$1
    local changes=$2
    local date=$(date '+%Y-%m-%d')
    
    mkdir -p "$(dirname "$CHANGELOG_FILE")"
    echo -e "\n## ${version} (${date})\n${changes}" >> "$CHANGELOG_FILE"
}

log_section "5.2.4 - Audit File Access Controls"

# Check audit log directory permissions
check_audit_directory() {
    local audit_dir="/var/log/audit"
    if [ -d "$audit_dir" ]; then
        local perms=$(stat -c "%a" "$audit_dir")
        local owner=$(stat -c "%U" "$audit_dir")
        local group=$(stat -c "%G" "$audit_dir")
        
        if [ "$perms" = "750" ] && [ "$owner" = "root" ] && [ "$group" = "root" ]; then
            log " - [PASS] Audit log directory has correct permissions (750) and ownership"
        else
            log " - [FAIL] Audit log directory has incorrect permissions/ownership (found: $perms $owner:$group)"
        fi
    else
        log " - [FAIL] Audit log directory does not exist"
    fi
}

# Check audit log file permissions
check_audit_files() {
    local audit_dir="/var/log/audit"
    if [ -d "$audit_dir" ]; then
        find "$audit_dir" -type f -name "audit*" | while read -r file; do
            local perms=$(stat -c "%a" "$file")
            local owner=$(stat -c "%U" "$file")
            local group=$(stat -c "%G" "$file")
            
            if [ "$perms" = "640" ] && [ "$owner" = "root" ] && [ "$group" = "root" ]; then
                log " - [PASS] Audit log file $file has correct permissions"
            else
                log " - [FAIL] Audit log file $file has incorrect permissions (found: $perms $owner:$group)"
            fi
        done
    fi
}

# Check audit tool permissions
check_audit_tools() {
    local tools=("/sbin/auditctl" "/sbin/aureport" "/sbin/ausearch" "/sbin/autrace" "/sbin/auditd" "/sbin/augenrules")
    
    for tool in "${tools[@]}"; do
        if [ -f "$tool" ]; then
            local perms=$(stat -c "%a" "$tool")
            local owner=$(stat -c "%U" "$tool")
            local group=$(stat -c "%G" "$tool")
            
            if [ "$perms" = "755" ] && [ "$owner" = "root" ] && [ "$group" = "root" ]; then
                log " - [PASS] Audit tool $tool has correct permissions"
            else
                log " - [FAIL] Audit tool $tool has incorrect permissions (found: $perms $owner:$group)"
            fi
        else
            log " - [FAIL] Audit tool $tool not found"
        fi
    done
}

# Run the audit file access checks
check_audit_directory
check_audit_files
check_audit_tools

# Add after initial variable declarations
MIN_DISK_SPACE=500000  # 500MB in KB

check_disk_space() {
    local available_space=$(df -k "$RESULT_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt "$MIN_DISK_SPACE" ]; then
        handle_error "Insufficient disk space. Required: ${MIN_DISK_SPACE}KB, Available: ${available_space}KB" "CRITICAL"
    fi
}

# Enhanced error handling with network checks
check_network_connectivity() {
    # Test basic network connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        handle_error "Network connectivity check failed" "WARNING"
    fi
    
    # Test DNS resolution
    if ! nslookup redhat.com >/dev/null 2>&1; then
        handle_error "DNS resolution check failed" "WARNING"
    fi
}

# Backup existing results
backup_existing_results() {
    if [ -f "$RESULT_FILE" ]; then
        local backup_file="${RESULT_FILE}.$(date +%Y%m%d_%H%M%S).bak"
        cp "$RESULT_FILE" "$backup_file" || handle_error "Failed to backup existing results" "WARNING"
        log "Backed up existing results to $backup_file" "INFO"
    fi
}

# Add before main execution
check_disk_space
check_network_connectivity
backup_existing_results

# Enhanced package checking with version verification
check_package_versions() {
    local -A required_versions=(
        ["nftables"]="0.9.3"
        ["firewalld"]="0.8.2"
    )

    for pkg in "${!required_versions[@]}"; do
        local installed_version=$(rpm -q --queryformat '%{VERSION}' "$pkg" 2>/dev/null)
        local required_version="${required_versions[$pkg]}"
        
        if [ -z "$installed_version" ]; then
            handle_error "Required package not found: $pkg" "CRITICAL"
        else
            if ! verify_version "$installed_version" "$required_version"; then
                handle_error "Package $pkg version mismatch. Required: $required_version, Found: $installed_version" "WARNING"
            else
                log "Package $pkg version check passed: $installed_version" "INFO"
            fi
        fi
    done
}

# Version comparison helper
verify_version() {
    local installed=$1
    local required=$2
    
    # Convert versions to comparable integers
    local installed_num=$(echo "$installed" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')
    local required_num=$(echo "$required" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')
    
    [ "$installed_num" -ge "$required_num" ]
}

# Add after the initial package checks
check_package_versions