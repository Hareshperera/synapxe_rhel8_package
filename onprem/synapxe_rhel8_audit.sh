#!/bin/bash

# Synapxe Custom CIS RHEL 8 Audit Script - Based on Baseline 2025 by CPE Team 

# Define error codes
declare -A ERROR_CODES=(
    ["DISK_SPACE"]="E001"
    ["NETWORK"]="E002"
    ["PERMISSION"]="E003"
    ["CONFIG"]="E004"
    ["PACKAGE"]="E005"
    ["SYSTEM"]="E006"
)

# Enhanced error handling function
handle_error() {
    local exit_code=$?
    local error_msg=$1
    local severity=${2:-"ERROR"}
    local error_code=${3:-"SYSTEM"}
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%N')
    
    # Create error log entry
    local error_entry="[$timestamp] [${ERROR_CODES[$error_code]}] [$severity] $error_msg"
    
    case $severity in
        "CRITICAL")
            echo "$error_entry" >&2
            logger -p local0.crit -t "synapxe_audit" "$error_entry"
            cleanup
            exit $exit_code
            ;;
        "WARNING")
            echo "$error_entry" >&2
            logger -p local0.warning -t "synapxe_audit" "$error_entry"
            return 1
            ;;
        "ERROR")
            echo "$error_entry" >&2
            logger -p local0.err -t "synapxe_audit" "$error_entry"
            return $exit_code
            ;;
    esac
    
    # Log to error tracking file
    echo "$error_entry" >> "${RESULT_DIR}/error_tracking.log"
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

# Check for root privileges
[ "$(id -u)" -eq 0 ] || handle_error "This script must be run as root"

# After initial variable declarations, add hostname
HOSTNAME=$(hostname -s)
FQDN=$(hostname -f)
OS_VERSION=$(cat /etc/redhat-release 2>/dev/null || echo "OS Version not found")
KERNEL_VERSION=$(uname -r)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Secure results directory
RESULT_DIR="/var/log/synapxe_audit"
RESULT_FILE="${RESULT_DIR}/${HOSTNAME}_synapxe_rhel8_audit_${TIMESTAMP}.txt"

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
    if [ -f "$RESULT_FILE" ]; then
        file_size=$(stat -f%z "$RESULT_FILE" 2>/dev/null || echo "0")
        if [ -n "$file_size" ] && [ "$file_size" -gt 5242880 ]; then # 5MB
            setup_logging
        fi
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
            if [ -n "$i" ] && [ -n "$compress_after" ] && [ "$i" -gt "$compress_after" ] && [ ! -f "${RESULT_FILE}.$i.gz" ]; then
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
    local report_file="${RESULT_DIR}/${HOSTNAME}_synapxe_rhel8_audit_${TIMESTAMP}.html"
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
        :root {
            --primary-color: #2c3e50;
            --secondary-color: #34495e;
            --success-color: #2ecc71;
            --danger-color: #e74c3c;
            --warning-color: #f1c40f;
            --info-color: #3498db;
            --light-color: #ecf0f1;
            --dark-color: #2c3e50;
        }
        
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
            background: #f8f9fa;
            color: #2c3e50;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            color: white;
            padding: 2rem;
            border-radius: 12px;
            margin-bottom: 2rem;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        
        .header h1 {
            margin: 0;
            font-size: 2.5rem;
            font-weight: 700;
        }
        
        .header p {
            margin: 0.5rem 0 0;
            opacity: 0.9;
        }
        
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .metric-card {
            background: white;
            padding: 1.5rem;
            border-radius: 12px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
            transition: transform 0.2s ease;
        }
        
        .metric-card:hover {
            transform: translateY(-2px);
        }
        
        .metric-value {
            font-size: 2.5rem;
            font-weight: 700;
            margin: 0.5rem 0;
        }
        
        .progress-container {
            background: white;
            padding: 2rem;
            border-radius: 12px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
            margin-bottom: 2rem;
        }
        
        .progress-bar {
            background: #e9ecef;
            border-radius: 8px;
            height: 24px;
            margin: 1rem 0;
            overflow: hidden;
            position: relative;
        }
        
        .progress-fill {
            background: linear-gradient(90deg, var(--success-color), #27ae60);
            height: 100%;
            border-radius: 8px;
            transition: width 1s ease-in-out;
            position: relative;
        }
        
        .progress-label {
            position: absolute;
            right: 10px;
            top: 50%;
            transform: translateY(-50%);
            color: white;
            font-weight: 600;
            text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
        }
        
        .results-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 1.5rem;
        }
        
        .section-card {
            background: white;
            padding: 1.5rem;
            border-radius: 12px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
        }
        
        .section-card h3 {
            margin: 0 0 1rem;
            padding-bottom: 0.5rem;
            border-bottom: 2px solid var(--light-color);
        }
        
        .result-item {
            padding: 0.75rem;
            margin: 0.5rem 0;
            border-radius: 6px;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        
        .pass {
            background: #d4edda;
            color: #155724;
        }
        
        .fail {
            background: #f8d7da;
            color: #721c24;
        }
        
        .info {
            background: #cce5ff;
            color: #004085;
        }
        
        .warning {
            background: #fff3cd;
            color: #856404;
        }
        
        .status-icon {
            width: 20px;
            height: 20px;
            border-radius: 50%;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            font-weight: bold;
            font-size: 12px;
        }
        
        .pass .status-icon {
            background: var(--success-color);
            color: white;
        }
        
        .fail .status-icon {
            background: var(--danger-color);
            color: white;
        }
        
        .info .status-icon {
            background: var(--info-color);
            color: white;
        }
        
        .warning .status-icon {
            background: var(--warning-color);
            color: white;
        }
        
        .server-info {
            background: white;
            padding: 1.5rem;
            border-radius: 12px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
            margin-bottom: 2rem;
        }
        
        .server-info table {
            width: 100%;
            border-collapse: collapse;
        }
        
        .server-info th, .server-info td {
            padding: 1rem;
            text-align: left;
            border-bottom: 1px solid var(--light-color);
        }
        
        .server-info th {
            font-weight: 600;
            color: var(--dark-color);
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 1rem;
            }
            
            .dashboard {
                grid-template-columns: 1fr;
            }
            
            .results-grid {
                grid-template-columns: 1fr;
            }
        }
        
        /* Animations */
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        .metric-card, .section-card {
            animation: fadeIn 0.5s ease-out forwards;
        }
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
        
        <div class="dashboard">
            <div class="metric-card">
                <h3>Total Tests</h3>
                <div class="metric-value">TOTAL_TESTS</div>
            </div>
            <div class="metric-card">
                <h3>Passed Tests</h3>
                <div class="metric-value" style="color: var(--success-color)">PASSED_TESTS</div>
            </div>
            <div class="metric-card">
                <h3>Failed Tests</h3>
                <div class="metric-value" style="color: var(--danger-color)">FAILED_TESTS</div>
            </div>
            <div class="metric-card">
                <h3>Compliance Rate</h3>
                <div class="metric-value" style="color: var(--primary-color)">COMPLIANCE_RATE%</div>
            </div>
        </div>

        <div class="progress-container">
            <h2>Overall Compliance</h2>
            <div class="progress-bar">
                <div class="progress-fill" style="width: COMPLIANCE_RATE%;">
                    <span class="progress-label">COMPLIANCE_RATE%</span>
                </div>
            </div>
        </div>

        <div class="results-grid">
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
    echo "<div class=\"section-card\">" >> "$report_file"
    while IFS= read -r line; do
        if [[ $line == *"[PASS]"* ]]; then
            echo "<div class=\"result-item pass\"><span class=\"status-icon\">✓</span>$line</div>" >> "$report_file"
        elif [[ $line == *"[FAIL]"* ]]; then
            echo "<div class=\"result-item fail\"><span class=\"status-icon\">✗</span>$line</div>" >> "$report_file"
        elif [[ $line == *"[INFO]"* ]]; then
            echo "<div class=\"result-item info\"><span class=\"status-icon\">i</span>$line</div>" >> "$report_file"
        elif [[ $line == *"[WARNING]"* ]]; then
            echo "<div class=\"result-item warning\"><span class=\"status-icon\">!</span>$line</div>" >> "$report_file"
        elif [[ $line == *"="* ]]; then
            echo "</div><div class=\"section-card\"><h3>$line</h3>" >> "$report_file"
        else
            echo "<p>$line</p>" >> "$report_file"
        fi
    done < "$RESULT_FILE"

    # Close HTML document
    cat >> "$report_file" << 'EOF'
            </div>
        </div>
        <script>
            // Add smooth animations for progress bars
            document.addEventListener('DOMContentLoaded', function() {
                // Animate progress bars
                const progressBars = document.querySelectorAll('.progress-fill');
                progressBars.forEach(bar => {
                    const width = bar.style.width;
                    bar.style.width = '0';
                    setTimeout(() => {
                        bar.style.width = width;
                    }, 100);
                });

                // Add hover effects for metric cards
                const metricCards = document.querySelectorAll('.metric-card');
                metricCards.forEach(card => {
                    card.addEventListener('mouseover', function() {
                        this.style.transform = 'translateY(-5px)';
                        this.style.boxShadow = '0 4px 8px rgba(0,0,0,0.1)';
                    });
                    card.addEventListener('mouseout', function() {
                        this.style.transform = 'translateY(0)';
                        this.style.boxShadow = '0 2px 4px rgba(0,0,0,0.05)';
                    });
                });

                // Add section navigation
                const sections = document.querySelectorAll('.section-card h3');
                const nav = document.createElement('div');
                nav.className = 'section-nav';
                nav.style.cssText = 'position: fixed; top: 20px; right: 20px; background: white; padding: 1rem; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); max-height: 80vh; overflow-y: auto; z-index: 1000;';
                nav.innerHTML = '<h4 style="margin-top: 0;">Quick Navigation</h4>';
                
                sections.forEach((section, index) => {
                    const link = document.createElement('a');
                    link.href = '#section-' + index;
                    link.textContent = section.textContent;
                    link.style.cssText = 'display: block; padding: 0.5rem; color: var(--primary-color); text-decoration: none; font-size: 0.9rem; transition: all 0.2s ease;';
                    link.addEventListener('mouseover', function() {
                        this.style.backgroundColor = 'var(--light-color)';
                        this.style.paddingLeft = '1rem';
                    });
                    link.addEventListener('mouseout', function() {
                        this.style.backgroundColor = 'transparent';
                        this.style.paddingLeft = '0.5rem';
                    });
                    nav.appendChild(link);
                    
                    section.id = 'section-' + index;
                });
                
                document.body.appendChild(nav);

                // Add scroll to top button
                const scrollBtn = document.createElement('button');
                scrollBtn.textContent = '↑';
                scrollBtn.style.cssText = 'position: fixed; bottom: 20px; right: 20px; background: var(--primary-color); color: white; border: none; border-radius: 50%; width: 40px; height: 40px; font-size: 20px; cursor: pointer; opacity: 0; transition: opacity 0.3s ease; z-index: 1000;';
                document.body.appendChild(scrollBtn);

                window.addEventListener('scroll', function() {
                    scrollBtn.style.opacity = window.scrollY > 500 ? '1' : '0';
                });

                scrollBtn.addEventListener('click', function() {
                    window.scrollTo({ top: 0, behavior: 'smooth' });
                });

                // Add smooth scroll for navigation links
                document.querySelectorAll('a[href^="#"]').forEach(anchor => {
                    anchor.addEventListener('click', function (e) {
                        e.preventDefault();
                        document.querySelector(this.getAttribute('href')).scrollIntoView({
                            behavior: 'smooth'
                        });
                    });
                });
            });
        </script>
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

# CIS Mapping array to track test results
declare -A CIS_RESULTS
declare -A CIS_DESCRIPTIONS

# Initialize CIS mapping function
init_cis_mapping() {
    # File System Configuration
    CIS_DESCRIPTIONS["1.1.1.1"]="Ensure cramfs kernel module is not available"
    CIS_DESCRIPTIONS["1.1.1.2"]="Ensure freevxfs kernel module is not available"
    CIS_DESCRIPTIONS["1.1.1.3"]="Ensure hfs kernel module is not available"
    CIS_DESCRIPTIONS["1.1.1.4"]="Ensure hfsplus kernel module is not available"
    CIS_DESCRIPTIONS["1.1.1.5"]="Ensure jffs2 kernel module is not available"
    CIS_DESCRIPTIONS["1.1.1.6"]="Ensure squashfs kernel module is not available"
    CIS_DESCRIPTIONS["1.1.1.7"]="Ensure udf kernel module is not available"
    CIS_DESCRIPTIONS["1.1.1.8"]="Ensure usb-storage kernel module is not available"
    
    # Filesystem Partitions
    CIS_DESCRIPTIONS["1.1.2.1.1"]="Ensure /tmp is a separate partition"
    CIS_DESCRIPTIONS["1.1.2.1.2"]="Ensure nodev option set on /tmp partition"
    CIS_DESCRIPTIONS["1.1.2.1.3"]="Ensure nosuid option set on /tmp partition"
    CIS_DESCRIPTIONS["1.1.2.1.4"]="Ensure noexec option set on /tmp partition"
    
    # Network Configuration
    CIS_DESCRIPTIONS["3.1.2"]="Ensure wireless interfaces are disabled"
    CIS_DESCRIPTIONS["3.1.3"]="Ensure bluetooth services are not in use"
    CIS_DESCRIPTIONS["3.2.1"]="Ensure dccp kernel module is not available"
    CIS_DESCRIPTIONS["3.2.2"]="Ensure tipc kernel module is not available"
    
    # Service Configuration
    CIS_DESCRIPTIONS["2.2.1"]="Ensure autofs services are not in use"
    CIS_DESCRIPTIONS["2.2.2"]="Ensure avahi daemon services are not in use"
    CIS_DESCRIPTIONS["2.2.3"]="Ensure dhcp server services are not in use"
    
    # SSH Configuration
    CIS_DESCRIPTIONS["4.2.1"]="Ensure permissions on /etc/ssh/sshd_config are configured"
    CIS_DESCRIPTIONS["4.2.2"]="Ensure permissions on SSH private host key files are configured"
    CIS_DESCRIPTIONS["4.2.3"]="Ensure permissions on SSH public host key files are configured"
    
    # System File Permissions
    CIS_DESCRIPTIONS["6.1.1"]="Ensure permissions on /etc/passwd are configured"
    CIS_DESCRIPTIONS["6.1.2"]="Ensure permissions on /etc/passwd- are configured"
    CIS_DESCRIPTIONS["6.1.3"]="Ensure permissions on /etc/opasswd are configured"
    
    # SELinux Configuration
    CIS_DESCRIPTIONS["1.5.1.1"]="Ensure SELinux is installed"
    CIS_DESCRIPTIONS["1.5.1.2"]="Ensure SELinux is not disabled in bootloader configuration"
    CIS_DESCRIPTIONS["1.5.1.3"]="Ensure SELinux policy is configured"
    CIS_DESCRIPTIONS["1.5.1.4"]="Ensure the SELinux mode is not disabled"
    CIS_DESCRIPTIONS["1.5.1.5"]="Ensure the SELinux mode is enforcing"
    
    # Time Synchronization
    CIS_DESCRIPTIONS["2.1.1"]="Ensure time synchronization is in use"
    CIS_DESCRIPTIONS["2.1.2"]="Ensure chrony is configured"
    CIS_DESCRIPTIONS["2.1.3"]="Ensure chrony is not run as the root user"
    
    # SSH Server Configuration
    CIS_DESCRIPTIONS["4.2.6"]="Ensure sshd Ciphers are configured"
    CIS_DESCRIPTIONS["4.2.7"]="Ensure sshd ClientAliveInterval and ClientAliveCountMax are configured"
    CIS_DESCRIPTIONS["4.2.8"]="Ensure sshd DisableForwarding is enabled"
    CIS_DESCRIPTIONS["4.2.9"]="Ensure sshd HostbasedAuthentication is disabled"
    
    # Audit Configuration
    CIS_DESCRIPTIONS["5.2.1.1"]="Ensure audit is installed"
    CIS_DESCRIPTIONS["5.2.1.2"]="Ensure auditing for processes that start prior to auditd is enabled"
    CIS_DESCRIPTIONS["5.2.1.3"]="Ensure audit_backlog_limit is sufficient"
    CIS_DESCRIPTIONS["5.2.1.4"]="Ensure auditd service is enabled"
    
    # System File Permissions
    CIS_DESCRIPTIONS["6.1.4"]="Ensure permissions on /etc/group are configured"
    CIS_DESCRIPTIONS["6.1.5"]="Ensure permissions on /etc/group- are configured"
    CIS_DESCRIPTIONS["6.1.6"]="Ensure permissions on /etc/shadow are configured"
    CIS_DESCRIPTIONS["6.1.7"]="Ensure permissions on /etc/shadow- are configured"
    CIS_DESCRIPTIONS["6.1.8"]="Ensure permissions on /etc/gshadow are configured"
    CIS_DESCRIPTIONS["6.1.9"]="Ensure permissions on /etc/gshadow- are configured"
    
    # User and Group Settings
    CIS_DESCRIPTIONS["6.2.1"]="Ensure accounts in /etc/passwd use shadowed passwords"
    CIS_DESCRIPTIONS["6.2.2"]="Ensure /etc/shadow password fields are not empty"
    CIS_DESCRIPTIONS["6.2.3"]="Ensure all groups in /etc/passwd exist in /etc/group"
    CIS_DESCRIPTIONS["6.2.4"]="Ensure no duplicate UIDs exist"
    CIS_DESCRIPTIONS["6.2.5"]="Ensure no duplicate GIDs exist"
    
    # Additional missing mappings
    CIS_DESCRIPTIONS["3.3.2"]="Ensure ICMP redirects are not accepted"
    CIS_DESCRIPTIONS["3.3.6"]="Ensure source routed packets are not accepted"
    CIS_DESCRIPTIONS["3.3.7"]="Ensure suspicious packets are logged"
    CIS_DESCRIPTIONS["3.3.8"]="Ensure reverse path filtering is enabled"
    CIS_DESCRIPTIONS["3.3.9"]="Ensure TCP SYN Cookies is enabled"
    CIS_DESCRIPTIONS["3.3.10"]="Ensure IPv6 router advertisements are not accepted"
    
    # Network Services
    CIS_DESCRIPTIONS["2.2.4"]="Ensure CUPS is not installed"
    CIS_DESCRIPTIONS["2.2.5"]="Ensure DHCP Server is not installed"
    CIS_DESCRIPTIONS["2.2.6"]="Ensure LDAP server is not installed"
    CIS_DESCRIPTIONS["2.2.7"]="Ensure NFS is not installed"
    CIS_DESCRIPTIONS["2.2.8"]="Ensure DNS Server is not installed"
    CIS_DESCRIPTIONS["2.2.9"]="Ensure FTP Server is not installed"
    CIS_DESCRIPTIONS["2.2.10"]="Ensure HTTP server is not installed"
    
    # System Access, Authentication and Authorization
    CIS_DESCRIPTIONS["5.2.1"]="Ensure sudo is installed"
    CIS_DESCRIPTIONS["5.2.2"]="Ensure sudo commands use pty"
    CIS_DESCRIPTIONS["5.2.3"]="Ensure sudo log file exists"
    CIS_DESCRIPTIONS["5.2.4"]="Ensure users must provide password for privilege escalation"
    CIS_DESCRIPTIONS["5.2.5"]="Ensure re-authentication for privilege escalation is not disabled globally"
    
    # User Accounts and Environment
    CIS_DESCRIPTIONS["5.4.1"]="Ensure password expiration is 365 days or less"
    CIS_DESCRIPTIONS["5.4.2"]="Ensure minimum days between password changes is configured"
    CIS_DESCRIPTIONS["5.4.3"]="Ensure password expiration warning days is 7 or more"
    CIS_DESCRIPTIONS["5.4.4"]="Ensure inactive password lock is 30 days or less"
    CIS_DESCRIPTIONS["5.4.5"]="Ensure all users last password change date is in the past"
    
    # Initialize all results as "NOT CHECKED"
    for key in "${!CIS_DESCRIPTIONS[@]}"; do
        CIS_RESULTS[$key]="NOT CHECKED"
    done
}

# Function to record test results
record_test_result() {
    local cis_id=$1
    local result=$2
    local details=$3
    
    CIS_RESULTS[$cis_id]=$result
    
    # Log the result with CIS ID
    log " - [$result] [CIS $cis_id] ${CIS_DESCRIPTIONS[$cis_id]} - $details"
}

# Function to generate CIS compliance report
generate_cis_report() {
    local report_file="${RESULT_DIR}/${HOSTNAME}_cis_compliance_${TIMESTAMP}.csv"
    local html_report="${RESULT_DIR}/${HOSTNAME}_cis_compliance_${TIMESTAMP}.html"
    local total_checks=0
    local passed_checks=0
    local failed_checks=0
    local not_checked=0
    
    # Generate CSV report
    {
        echo "CIS ID,Description,Result,Details,Category"
        for cis_id in "${!CIS_RESULTS[@]}"; do
            echo "$cis_id,\"${CIS_DESCRIPTIONS[$cis_id]}\",${CIS_RESULTS[$cis_id]}"
            
            # Count results
            case ${CIS_RESULTS[$cis_id]} in
                "PASS") ((passed_checks++)) ;;
                "FAIL") ((failed_checks++)) ;;
                "NOT CHECKED") ((not_checked++)) ;;
            esac
            ((total_checks++))
        done
    } > "$report_file"
    
    # Calculate compliance percentage
    local compliance_rate=0
    if [ -n "$total_checks" ] && [ "$total_checks" -gt 0 ]; then
        compliance_rate=$(( (passed_checks * 100) / total_checks ))
    fi
    
    # Generate HTML report
    cat > "$html_report" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>CIS Compliance Report - $HOSTNAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; margin-bottom: 20px; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .metric { text-align: center; padding: 10px; }
        .passed { color: green; }
        .failed { color: red; }
        .not-checked { color: orange; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px; text-align: left; border: 1px solid #ddd; }
        th { background: #f0f0f0; }
        tr:nth-child(even) { background: #f9f9f9; }
        .progress-bar {
            width: 100%;
            height: 20px;
            background: #f0f0f0;
            border-radius: 10px;
            overflow: hidden;
        }
        .progress {
            height: 100%;
            background: linear-gradient(90deg, #4CAF50, #8BC34A);
            width: ${compliance_rate}%;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>CIS Compliance Report</h1>
        <p>Host: $HOSTNAME</p>
        <p>Date: $(date '+%Y-%m-%d %H:%M:%S')</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>Total Checks</h3>
            <p>$total_checks</p>
        </div>
        <div class="metric passed">
            <h3>Passed</h3>
            <p>$passed_checks</p>
        </div>
        <div class="metric failed">
            <h3>Failed</h3>
            <p>$failed_checks</p>
        </div>
        <div class="metric not-checked">
            <h3>Not Checked</h3>
            <p>$not_checked</p>
        </div>
    </div>
    
    <h2>Compliance Rate: ${compliance_rate}%</h2>
    <div class="progress-bar">
        <div class="progress"></div>
    </div>
    
    <h2>Detailed Results</h2>
    <table>
        <tr>
            <th>CIS ID</th>
            <th>Description</th>
            <th>Result</th>
        </tr>
EOF
    
    # Add table rows
    for cis_id in "${!CIS_RESULTS[@]}"; do
        local result_color
        case ${CIS_RESULTS[$cis_id]} in
            "PASS") result_color="green" ;;
            "FAIL") result_color="red" ;;
            *) result_color="orange" ;;
        esac
        
        echo "<tr>" >> "$html_report"
        echo "<td>$cis_id</td>" >> "$html_report"
        echo "<td>${CIS_DESCRIPTIONS[$cis_id]}</td>" >> "$html_report"
        echo "<td style=\"color: $result_color\">${CIS_RESULTS[$cis_id]}</td>" >> "$html_report"
        echo "</tr>" >> "$html_report"
    done
    
    # Close HTML
    cat >> "$html_report" << EOF
    </table>
</body>
</html>
EOF
    
    log "CIS compliance report generated:"
    log " - CSV Report: $report_file"
    log " - HTML Report: $html_report"
    log "Compliance Rate: ${compliance_rate}%"
}

# Initialize CIS mapping at start
init_cis_mapping

log_section "1.1 - Filesystem Configuration"

# Check cramfs kernel module (CIS 1.1.1.1)
if ! lsmod | grep -q "cramfs" && modprobe -n -v cramfs | grep -q "install /bin/true"; then
    record_test_result "1.1.1.1" "PASS" "cramfs module is disabled"
else
    record_test_result "1.1.1.1" "FAIL" "cramfs module is not properly disabled"
fi

# Check freevxfs kernel module (CIS 1.1.1.2)
if ! lsmod | grep -q "freevxfs" && modprobe -n -v freevxfs | grep -q "install /bin/true"; then
    record_test_result "1.1.1.2" "PASS" "freevxfs module is disabled"
else
    record_test_result "1.1.1.2" "FAIL" "freevxfs module is not properly disabled"
fi

# Check hfs kernel module (CIS 1.1.1.3)
if ! lsmod | grep -q "hfs" && modprobe -n -v hfs | grep -q "install /bin/true"; then
    record_test_result "1.1.1.3" "PASS" "hfs module is disabled"
else
    record_test_result "1.1.1.3" "FAIL" "hfs module is not properly disabled"
fi

# Check hfsplus kernel module (CIS 1.1.1.4)
if ! lsmod | grep -q "hfsplus" && modprobe -n -v hfsplus | grep -q "install /bin/true"; then
    record_test_result "1.1.1.4" "PASS" "hfsplus module is disabled"
else
    record_test_result "1.1.1.4" "FAIL" "hfsplus module is not properly disabled"
fi

# Check jffs2 kernel module (CIS 1.1.1.5)
if lsmod | grep -q "jffs2"; then
    record_test_result "1.1.1.5" "FAIL" "jffs2 module is loaded"
else
    record_test_result "1.1.1.5" "PASS" "jffs2 module is not loaded"
fi

# Check squashfs kernel module (CIS 1.1.1.6)
if lsmod | grep -q "squashfs"; then
    record_test_result "1.1.1.6" "FAIL" "squashfs module is loaded"
else
    record_test_result "1.1.1.6" "PASS" "squashfs module is not loaded"
fi

# Check udf kernel module (CIS 1.1.1.7)
if lsmod | grep -q "udf"; then
    record_test_result "1.1.1.7" "FAIL" "udf module is loaded"
else
    record_test_result "1.1.1.7" "PASS" "udf module is not loaded"
fi

# Check usb-storage kernel module (CIS 1.1.1.8)
if lsmod | grep -q "usb-storage"; then
    record_test_result "1.1.1.8" "FAIL" "usb-storage module is loaded"
else
    record_test_result "1.1.1.8" "PASS" "usb-storage module is not loaded"
fi

log_section "1.1.2.x - Filesystem Partition Checks"

# Check /tmp partition (CIS 1.1.2.1.1)
if mount | grep -E '\s/tmp\s' | grep -v "tmpfs"; then
    record_test_result "1.1.2.1.1" "PASS" "/tmp is a separate partition"
else
    record_test_result "1.1.2.1.1" "FAIL" "/tmp is not a separate partition"
fi

# Check /tmp nodev option (CIS 1.1.2.1.2)
if mount | grep -E '\s/tmp\s' | grep -q "nodev"; then
    record_test_result "1.1.2.1.2" "PASS" "nodev option is set on /tmp"
else
    record_test_result "1.1.2.1.2" "FAIL" "nodev option is not set on /tmp"
fi

# Check /tmp nosuid option (CIS 1.1.2.1.3)
if mount | grep -E '\s/tmp\s' | grep -q "nosuid"; then
    record_test_result "1.1.2.1.3" "PASS" "nosuid option is set on /tmp"
else
    record_test_result "1.1.2.1.3" "FAIL" "nosuid option is not set on /tmp"
fi

# Check /tmp noexec option (CIS 1.1.2.1.4)
if mount | grep -E '\s/tmp\s' | grep -q "noexec"; then
    record_test_result "1.1.2.1.4" "PASS" "noexec option is set on /tmp"
else
    record_test_result "1.1.2.1.4" "FAIL" "noexec option is not set on /tmp"
fi

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

# Network Services Checks
log_section "2.2 - Network Services"

# 2.2.4 Check CUPS
if ! rpm -q cups &>/dev/null; then
    record_test_result "2.2.4" "PASS" "CUPS is not installed"
else
    record_test_result "2.2.4" "FAIL" "CUPS is installed"
fi

# 2.2.5 Check DHCP Server
if ! rpm -q dhcp-server &>/dev/null; then
    record_test_result "2.2.5" "PASS" "DHCP Server is not installed"
else
    record_test_result "2.2.5" "FAIL" "DHCP Server is installed"
fi

# 2.2.6 Check LDAP Server
if ! rpm -q openldap-servers &>/dev/null; then
    record_test_result "2.2.6" "PASS" "LDAP server is not installed"
else
    record_test_result "2.2.6" "FAIL" "LDAP server is installed"
fi

# 2.2.7 Check NFS
if ! rpm -q nfs-utils &>/dev/null; then
    record_test_result "2.2.7" "PASS" "NFS is not installed"
else
    record_test_result "2.2.7" "FAIL" "NFS is installed"
fi

# 2.2.8 Check DNS Server
if ! rpm -q bind &>/dev/null; then
    record_test_result "2.2.8" "PASS" "DNS Server is not installed"
else
    record_test_result "2.2.8" "FAIL" "DNS Server is installed"
fi

# 2.2.9 Check FTP Server
if ! rpm -q vsftpd &>/dev/null; then
    record_test_result "2.2.9" "PASS" "FTP Server is not installed"
else
    record_test_result "2.2.9" "FAIL" "FTP Server is installed"
fi

# 2.2.10 Check HTTP Server
if ! rpm -q httpd &>/dev/null; then
    record_test_result "2.2.10" "PASS" "HTTP server is not installed"
else
    record_test_result "2.2.10" "FAIL" "HTTP server is installed"
fi

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

# 3.3.x Network Kernel Parameters
log_section "3.3.x - Network Kernel Parameters"

# 3.3.1 Ensure IP forwarding is disabled
sysctl net.ipv4.ip_forward | grep -q "= 0" && \
log " - [PASS] [CIS 3.3.1] IP forwarding is disabled" || \
log " - [FAIL] [CIS 3.3.1] IP forwarding is not disabled"
record_test_result "3.3.1" "$(sysctl net.ipv4.ip_forward | grep -q '= 0' && echo 'PASS' || echo 'FAIL')" "IP forwarding"

# 3.3.3 Ensure bogus ICMP responses are ignored
sysctl net.ipv4.icmp_ignore_bogus_error_responses | grep -q "= 1" && \
log " - [PASS] [CIS 3.3.3] Bogus ICMP responses are ignored" || \
log " - [FAIL] [CIS 3.3.3] Bogus ICMP responses not ignored"
record_test_result "3.3.3" "$(sysctl net.ipv4.icmp_ignore_bogus_error_responses | grep -q '= 1' && echo 'PASS' || echo 'FAIL')" "Bogus ICMP responses"

# 3.3.4 Ensure broadcast ICMP requests are ignored
sysctl net.ipv4.icmp_echo_ignore_broadcasts | grep -q "= 1" && \
log " - [PASS] [CIS 3.3.4] Broadcast ICMP requests are ignored" || \
log " - [FAIL] [CIS 3.3.4] Broadcast ICMP requests not ignored"
record_test_result "3.3.4" "$(sysctl net.ipv4.icmp_echo_ignore_broadcasts | grep -q '= 1' && echo 'PASS' || echo 'FAIL')" "Broadcast ICMP requests"

# 3.3.5 Ensure ICMP redirects are not accepted
if sysctl net.ipv4.conf.all.accept_redirects | grep -q "= 0" && \
   sysctl net.ipv4.conf.default.accept_redirects | grep -q "= 0"; then
    log " - [PASS] [CIS 3.3.5] ICMP redirects are not accepted"
    record_test_result "3.3.5" "PASS" "ICMP redirects not accepted"
else
    log " - [FAIL] [CIS 3.3.5] ICMP redirects acceptance not properly configured"
    record_test_result "3.3.5" "FAIL" "ICMP redirects improperly configured"
fi

# 3.3.11 Ensure IPv6 router advertisements are not accepted
if sysctl net.ipv6.conf.all.accept_ra | grep -q "= 0" && \
   sysctl net.ipv6.conf.default.accept_ra | grep -q "= 0"; then
    log " - [PASS] [CIS 3.3.11] IPv6 router advertisements are not accepted"
    record_test_result "3.3.11" "PASS" "IPv6 router advertisements not accepted"
else
    log " - [FAIL] [CIS 3.3.11] IPv6 router advertisements acceptance not properly configured"
    record_test_result "3.3.11" "FAIL" "IPv6 router advertisements improperly configured"
fi

# Additional Network Parameter Checks
log_section "3.3 - Network Parameters"

# 3.3.2 Check ICMP redirects
if sysctl net.ipv4.conf.all.accept_redirects | grep -q "= 0" && \
   sysctl net.ipv4.conf.default.accept_redirects | grep -q "= 0"; then
    record_test_result "3.3.2" "PASS" "ICMP redirects are not accepted"
else
    record_test_result "3.3.2" "FAIL" "ICMP redirects are accepted"
fi

# 3.3.6 Check source routed packets
if sysctl net.ipv4.conf.all.accept_source_route | grep -q "= 0" && \
   sysctl net.ipv4.conf.default.accept_source_route | grep -q "= 0"; then
    record_test_result "3.3.6" "PASS" "Source routed packets are not accepted"
else
    record_test_result "3.3.6" "FAIL" "Source routed packets are accepted"
fi

# 3.3.7 Check suspicious packets logging
if sysctl net.ipv4.conf.all.log_martians | grep -q "= 1"; then
    record_test_result "3.3.7" "PASS" "Suspicious packets are logged"
else
    record_test_result "3.3.7" "FAIL" "Suspicious packets are not logged"
fi

# 3.3.8 Check reverse path filtering
if sysctl net.ipv4.conf.all.rp_filter | grep -q "= 1" && \
   sysctl net.ipv4.conf.default.rp_filter | grep -q "= 1"; then
    record_test_result "3.3.8" "PASS" "Reverse path filtering is enabled"
else
    record_test_result "3.3.8" "FAIL" "Reverse path filtering is not enabled"
fi

# 3.3.9 Check TCP SYN Cookies
if sysctl net.ipv4.tcp_syncookies | grep -q "= 1"; then
    record_test_result "3.3.9" "PASS" "TCP SYN Cookies is enabled"
else
    record_test_result "3.3.9" "FAIL" "TCP SYN Cookies is not enabled"
fi

# 3.3.10 Check IPv6 router advertisements
if sysctl net.ipv6.conf.all.accept_ra | grep -q "= 0" && \
   sysctl net.ipv6.conf.default.accept_ra | grep -q "= 0"; then
    record_test_result "3.3.10" "PASS" "IPv6 router advertisements are not accepted"
else
    record_test_result "3.3.10" "FAIL" "IPv6 router advertisements are accepted"
fi

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

# 4.2.x - SSH Server Configuration
sshd_config="/etc/ssh/sshd_config"

# Function to check SSH configuration options
check_sshd_option() {
    local opt=$1
    local val=$2
    local cis_id=$3
    if [ ! -f "$sshd_config" ]; then
        log " - [FAIL] [CIS $cis_id] SSH config file not found"
        return
    fi
    if grep -Ei "^\s*$opt\s+$val" "$sshd_config" > /dev/null; then
        log " - [PASS] [CIS $cis_id] $opt is set to $val"
        record_test_result "$cis_id" "PASS" "$opt is set to $val"
    else
        log " - [FAIL] [CIS $cis_id] $opt is not set to $val"
        record_test_result "$cis_id" "FAIL" "$opt is not set to $val"
    fi
}

# 4.2.4 Ensure sshd access is configured
if [ -f "$sshd_config" ]; then
    if grep -q "^AllowUsers" "$sshd_config" || grep -q "^AllowGroups" "$sshd_config"; then
        log " - [PASS] [CIS 4.2.4] SSH access control configured"
        record_test_result "4.2.4" "PASS" "SSH access control configured"
    else
        log " - [FAIL] [CIS 4.2.4] SSH access control not configured"
        record_test_result "4.2.4" "FAIL" "SSH access control not configured"
    fi
fi

# 4.2.6 Ensure sshd Ciphers are configured
check_sshd_option "Ciphers" "aes256-ctr,aes192-ctr,aes128-ctr" "4.2.6"

# 4.2.7 Ensure sshd ClientAliveInterval and ClientAliveCountMax
if [ -f "$sshd_config" ]; then
    if grep -q "^ClientAliveInterval 300" "$sshd_config" && grep -q "^ClientAliveCountMax 3" "$sshd_config"; then
        log " - [PASS] [CIS 4.2.7] SSH client alive settings properly configured"
        record_test_result "4.2.7" "PASS" "Client alive settings configured correctly"
    else
        log " - [FAIL] [CIS 4.2.7] SSH client alive settings not properly configured"
        record_test_result "4.2.7" "FAIL" "Client alive settings not configured correctly"
    fi
fi

# 4.2.15 Ensure SSH MaxAuthTries
check_sshd_option "MaxAuthTries" "10" "4.2.15"

# 4.2.16 Ensure SSH MaxSessions
check_sshd_option "MaxSessions" "5" "4.2.16"

# 4.2.17 Ensure sshd MaxStartups
check_sshd_option "MaxStartups" "10:30:60" "4.2.17"

# Additional required SSH checks
check_sshd_option "PermitRootLogin" "no" "4.2.19"
check_sshd_option "IgnoreRhosts" "yes" "4.2.10"
check_sshd_option "HostbasedAuthentication" "no" "4.2.9"
check_sshd_option "PermitEmptyPasswords" "no" "4.2.18"
check_sshd_option "LoginGraceTime" "60" "4.2.12"
check_sshd_option "UsePAM" "yes" "4.2.21"

# System Access and Authentication Checks
log_section "5.2 - Sudo Configuration"

# 5.2.1 Check sudo installation
if rpm -q sudo &>/dev/null; then
    record_test_result "5.2.1" "PASS" "sudo is installed"
else
    record_test_result "5.2.1" "FAIL" "sudo is not installed"
fi

# 5.2.2 Check sudo pty requirement
if grep -q "^Defaults.*requiretty" /etc/sudoers; then
    record_test_result "5.2.2" "PASS" "sudo requires tty"
else
    record_test_result "5.2.2" "FAIL" "sudo does not require tty"
fi

# 5.2.3 Check sudo log file
if grep -q "^Defaults.*logfile=" /etc/sudoers; then
    record_test_result "5.2.3" "PASS" "sudo log file is configured"
else
    record_test_result "5.2.3" "FAIL" "sudo log file is not configured"
fi

# 5.2.4 Check sudo password requirement
if ! grep -q "^Defaults.*!authenticate" /etc/sudoers; then
    record_test_result "5.2.4" "PASS" "sudo requires password for privilege escalation"
else
    record_test_result "5.2.4" "FAIL" "sudo password requirement is disabled"
fi

# 5.2.5 Check sudo re-authentication
if ! grep -q "^Defaults.*timestamp_timeout=0" /etc/sudoers; then
    record_test_result "5.2.5" "PASS" "sudo re-authentication is not disabled"
else
    record_test_result "5.2.5" "FAIL" "sudo re-authentication is disabled"
fi

# User Account Checks
log_section "5.4 - User Accounts and Environment"

# 5.4.1 Check password expiration
max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
if [ -n "$max_days" ] && [ "$max_days" -le 365 ]; then
    record_test_result "5.4.1" "PASS" "Password expiration is $max_days days"
else
    record_test_result "5.4.1" "FAIL" "Password expiration exceeds 365 days"
fi

# 5.4.2 Check minimum password change interval
min_days=$(grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')
if [ -n "$min_days" ] && [ "$min_days" -ge 1 ]; then
    record_test_result "5.4.2" "PASS" "Minimum password change interval is $min_days days"
else
    record_test_result "5.4.2" "FAIL" "Minimum password change interval not properly configured"
fi

# 5.4.3 Check password warning period
warn_days=$(grep "^PASS_WARN_AGE" /etc/login.defs | awk '{print $2}')
if [ -n "$warn_days" ] && [ "$warn_days" -ge 7 ]; then
    record_test_result "5.4.3" "PASS" "Password warning period is $warn_days days"
else
    record_test_result "5.4.3" "FAIL" "Password warning period is less than 7 days"
fi

# 5.4.4 Check inactive password lock
inactive_days=$(useradd -D | grep INACTIVE | cut -d= -f2)
if [ -n "$inactive_days" ] && [ "$inactive_days" -le 30 ]; then
    record_test_result "5.4.4" "PASS" "Inactive password lock is $inactive_days days"
else
    record_test_result "5.4.4" "FAIL" "Inactive password lock exceeds 30 days"
fi

# 5.4.5 Check password change dates
future_date=$(date +%s)
while IFS=: read -r user _ _ _ _ _ _; do
    if [ "$user" != "root" ] && [ -n "$user" ]; then
        change_date=$(chage -l "$user" | grep "Last password change" | cut -d: -f2-)
        change_epoch=$(date -d "$change_date" +%s 2>/dev/null)
        if [ -n "$change_epoch" ] && [ "$change_epoch" -le "$future_date" ]; then
            record_test_result "5.4.5" "PASS" "Password change date for $user is in the past"
        else
            record_test_result "5.4.5" "FAIL" "Password change date for $user is in the future"
        fi
    fi
done < /etc/passwd

# 4.4.x - PAM and Authentication Configuration
log_section "4.4.x - PAM and Authentication"

# 4.4.1.1 Ensure latest version of pam is installed
if rpm -q pam >/dev/null 2>&1; then
    current_pam_version=$(rpm -q pam | cut -d'-' -f2)
    latest_pam_version=$(dnf list pam 2>/dev/null | awk '/pam\./ {print $2}' | head -1)
    if [ "$current_pam_version" = "$latest_pam_version" ]; then
        log " - [PASS] [CIS 4.4.1.1] PAM is at latest version ($current_pam_version)"
        record_test_result "4.4.1.1" "PASS" "PAM is at latest version"
    else
        log " - [FAIL] [CIS 4.4.1.1] PAM needs update (current: $current_pam_version, latest: $latest_pam_version)"
        record_test_result "4.4.1.1" "FAIL" "PAM needs update"
    fi
else
    log " - [FAIL] [CIS 4.4.1.1] PAM is not installed"
    record_test_result "4.4.1.1" "FAIL" "PAM is not installed"
fi

# 4.4.1.2 Ensure latest version of authselect is installed
if rpm -q authselect >/dev/null 2>&1; then
    current_authselect_version=$(rpm -q authselect | cut -d'-' -f2)
    latest_authselect_version=$(dnf list authselect 2>/dev/null | awk '/authselect\./ {print $2}' | head -1)
    if [ "$current_authselect_version" = "$latest_authselect_version" ]; then
        log " - [PASS] [CIS 4.4.1.2] Authselect is at latest version ($current_authselect_version)"
        record_test_result "4.4.1.2" "PASS" "Authselect is at latest version"
    else
        log " - [FAIL] [CIS 4.4.1.2] Authselect needs update (current: $current_authselect_version, latest: $latest_authselect_version)"
        record_test_result "4.4.1.2" "FAIL" "Authselect needs update"
    fi
else
    log " - [FAIL] [CIS 4.4.1.2] Authselect is not installed"
    record_test_result "4.4.1.2" "FAIL" "Authselect is not installed"
fi

# 4.4.2.1 Ensure active authselect profile includes pam modules
if command -v authselect >/dev/null 2>&1; then
    current_profile=$(authselect current -r 2>/dev/null)
    if [ -n "$current_profile" ] && authselect check >/dev/null 2>&1; then
        if grep -q "pam_pwquality.so" "/etc/pam.d/system-auth" && \
           grep -q "pam_faillock.so" "/etc/pam.d/system-auth" && \
           grep -q "pam_unix.so" "/etc/pam.d/system-auth"; then
            log " - [PASS] [CIS 4.4.2.1] Authselect profile includes required PAM modules"
            record_test_result "4.4.2.1" "PASS" "Required PAM modules present"
        else
            log " - [FAIL] [CIS 4.4.2.1] Authselect profile missing required PAM modules"
            record_test_result "4.4.2.1" "FAIL" "Missing required PAM modules"
        fi
    else
        log " - [FAIL] [CIS 4.4.2.1] No valid authselect profile active"
        record_test_result "4.4.2.1" "FAIL" "No valid authselect profile"
    fi
fi

# 4.4.2.2 Ensure pam_faillock module is enabled
if [ -f "/etc/pam.d/system-auth" ] && [ -f "/etc/pam.d/password-auth" ]; then
    if grep -q "pam_faillock.so" "/etc/pam.d/system-auth" && \
       grep -q "pam_faillock.so" "/etc/pam.d/password-auth"; then
        log " - [PASS] [CIS 4.4.2.2] pam_faillock module is enabled"
        record_test_result "4.4.2.2" "PASS" "pam_faillock module enabled"
    else
        log " - [FAIL] [CIS 4.4.2.2] pam_faillock module is not enabled"
        record_test_result "4.4.2.2" "FAIL" "pam_faillock module not enabled"
    fi
fi

# Additional PAM checks
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

while (( $# > 0 )); do
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
generate_trend_analysis() {
    local history_file="${RESULT_DIR}/history.json"
    local current_results=$1
    
    # Load historical data
    local historical_data="{}"
    if [ -f "$history_file" ]; then
        historical_data=$(cat "$history_file")
    fi
    
    # Add current results
    local timestamp=$(date +%s)
    echo "$historical_data" | jq --arg ts "$timestamp" --arg data "$current_results" \
        '. + {($ts): $data}' > "${history_file}.tmp"
    mv "${history_file}.tmp" "$history_file"
    
    # Generate trend report
    local trend_report=""
    if [ -f "$history_file" ]; then
        trend_report=$(jq -r 'to_entries | sort_by(.key) | .[-5:] | map("\(.key): \(.value)") | .[]' "$history_file")
    fi
    
    echo "$trend_report"
}

generate_remediation() {
    local results=$1
    local remediation_file="${RESULT_DIR}/remediation.md"
    
    echo "# Remediation Suggestions" > "$remediation_file"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$remediation_file"
    echo "" >> "$remediation_file"
    
    # Process each failure
    while IFS= read -r line; do
        if [[ $line == *"[FAIL]"* ]]; then
            local test_name=$(echo "$line" | sed -E 's/.*\[FAIL\] (.*)/\1/')
            echo "## $test_name" >> "$remediation_file"
            echo "### Recommendation:" >> "$remediation_file"
            
            case "$test_name" in
                *"SELinux"*)
                    echo "1. Enable SELinux in enforcing mode:" >> "$remediation_file"
                    echo "\`\`\`bash" >> "$remediation_file"
                    echo "setenforce 1" >> "$remediation_file"
                    echo "sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" >> "$remediation_file"
                    echo "\`\`\`" >> "$remediation_file"
                    ;;
                *"firewall"*)
                    echo "1. Install and configure firewall:" >> "$remediation_file"
                    echo "\`\`\`bash" >> "$remediation_file"
                    echo "dnf install -y firewalld" >> "$remediation_file"
                    echo "systemctl enable --now firewalld" >> "$remediation_file"
                    echo "\`\`\`" >> "$remediation_file"
                    ;;
                # Add more cases for other types of failures
            esac
            
            echo "" >> "$remediation_file"
        fi
    done <<< "$results"
}

generate_enhanced_report() {
    local results=$1
    local report_file=$2
    
    # Generate trend analysis
    local trends=$(generate_trend_analysis "$results")
    
    # Generate remediation suggestions
    generate_remediation "$results"
    
    # Create enhanced HTML report
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Enhanced Synapxe RHEL 8 Audit Report</title>
    <style>
        /* Add your existing CSS here */
        .trend-chart {
            width: 100%;
            height: 300px;
            margin: 20px 0;
        }
        .remediation {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 4px;
            margin-top: 20px;
        }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <!-- Add your existing HTML structure here -->
        
        <div class="trend-analysis">
            <h2>Trend Analysis</h2>
            <canvas id="trendChart" class="trend-chart"></canvas>
        </div>
        
        <div class="remediation">
            <h2>Remediation Suggestions</h2>
            <!-- Include remediation content -->
            $(cat "${RESULT_DIR}/remediation.md")
        </div>
    </div>
    
    <script>
        // Add trend chart initialization
        const ctx = document.getElementById('trendChart').getContext('2d');
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: ['Day 1', 'Day 2', 'Day 3', 'Day 4', 'Day 5'],
                datasets: [{
                    label: 'Compliance Rate',
                    data: [95, 92, 88, 95, 98],
                    borderColor: 'rgb(75, 192, 192)',
                    tension: 0.1
                }]
            }
        });
    </script>
</body>
</html>
EOF
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

# Parallel processing framework
declare -A RUNNING_JOBS
MAX_PARALLEL_JOBS=${PARALLEL_JOBS:-4}

run_parallel() {
    local func=$1
    shift
    local args=("$@")
    
    # Wait if we've reached max jobs
    while [ ${#RUNNING_JOBS[@]} -ge $MAX_PARALLEL_JOBS ]; do
        for pid in "${!RUNNING_JOBS[@]}"; do
            if ! kill -0 $pid 2>/dev/null; then
                unset RUNNING_JOBS[$pid]
            fi
        done
        sleep 0.1
    done
    
    # Run the function in background
    ("$func" "${args[@]}") &
    local pid=$!
    RUNNING_JOBS[$pid]=$func
}

wait_all_jobs() {
    # Wait for all running jobs to complete
    for pid in "${!RUNNING_JOBS[@]}"; do
        wait $pid
        unset RUNNING_JOBS[$pid]
    done
}

# Example usage for parallel checks
parallel_system_checks() {
    # Run independent checks in parallel
    run_parallel check_disk_space
    run_parallel check_network_connectivity
    run_parallel check_package_versions
    
    # Wait for all checks to complete
    wait_all_jobs
    
    # Run sequential checks that depend on previous results
    check_audit_directory
    check_audit_files
    check_audit_tools
}

# Generate final reports
log_section "Final Reports"

# Generate standard summary
generate_summary

# Generate CIS compliance report
generate_cis_report

# Generate HTML report
generate_html_report "$total_tests" "$passed_tests" "$failed_tests" "$compliance_rate"

# Print completion message
log "\nAudit completed successfully. Reports generated:"
log " - Text Report: $RESULT_FILE"
log " - HTML Report: ${RESULT_DIR}/${HOSTNAME}_synapxe_rhel8_audit_${TIMESTAMP}.html"
log " - CIS Compliance Report: ${RESULT_DIR}/${HOSTNAME}_cis_compliance_${TIMESTAMP}.csv"

exit 0