#!/bin/bash

# Synapxe Custom CIS RHEL 8 Audit Script - Based on Baseline 2025 by CPE Team 

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
HTML_TEMPLATE="${CONFIG_DIR}/report_template.html"

# Define error codes
declare -A ERROR_CODES=(
    ["DISK_SPACE"]="E001"
    ["NETWORK"]="E002"
    ["PERMISSION"]="E003"
    ["CONFIG"]="E004"
    ["PACKAGE"]="E005"
    ["SYSTEM"]="E006"
)

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        handle_error "Configuration file not found at $CONFIG_FILE" "CRITICAL" "CONFIG"
    fi
}

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

# Initialize environment
init_environment() {
    # Check for root privileges
    [ "$(id -u)" -eq 0 ] || handle_error "This script must be run as root" "CRITICAL" "PERMISSION"
    
    # Set up system information
    HOSTNAME=$(hostname -s)
    FQDN=$(hostname -f)
    OS_VERSION=$(cat /etc/redhat-release 2>/dev/null || echo "OS Version not found")
    KERNEL_VERSION=$(uname -r)
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    
    # Set up directories
    RESULT_DIR="/var/log/synapxe_audit"
    RESULT_FILE="${RESULT_DIR}/${HOSTNAME}_synapxe_rhel8_audit_${TIMESTAMP}.txt"
    
    # Create secure results directory
    mkdir -p "${RESULT_DIR}" || handle_error "Failed to create results directory" "CRITICAL" "PERMISSION"
    chmod 750 "${RESULT_DIR}" || handle_error "Failed to set directory permissions" "CRITICAL" "PERMISSION"
    
    # Initialize results file
    > "$RESULT_FILE" || handle_error "Failed to create results file" "CRITICAL" "PERMISSION"
}

# Check system requirements
check_requirements() {
    # Check required packages
    for pkg in "${!PACKAGE_VERSIONS[@]}"; do
        local version=${PACKAGE_VERSIONS[$pkg]}
        rpm -q "$pkg" >/dev/null 2>&1 || handle_error "Required package not found: $pkg. Please install version $version" "CRITICAL" "PACKAGE"
    done
    
    # Check required commands
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || handle_error "Required command not found: $cmd" "CRITICAL" "SYSTEM"
    done
    
    # Check disk space
    check_disk_space
    
    # Check network connectivity if needed
    [ "$CHECK_NETWORK" = "true" ] && check_network_connectivity
}

# Function to handle errors
handle_error() {
    local message="$1"
    local level="${2:-ERROR}"
    echo "[${level}] ${message}" >&2
    exit 1
}

# Function to calculate test metrics accurately
calculate_test_metrics() {
    local result_file="$1"
    local -n total_ref="$2"
    local -n passed_ref="$3"
    local -n failed_ref="$4"
    local -n info_ref="$5"
    local -n warn_ref="$6"
    
    # Reset counters
    total_ref=0
    passed_ref=0
    failed_ref=0
    info_ref=0
    warn_ref=0
    
    # Process file line by line
    while IFS= read -r line; do
        # Skip empty lines and section headers
        [[ -z "$line" || "$line" == *"====="* ]] && continue
        
        # Count results
        if [[ "$line" == *"[PASS]"* ]]; then
            ((passed_ref++))
            ((total_ref++))
        elif [[ "$line" == *"[FAIL]"* ]]; then
            ((failed_ref++))
            ((total_ref++))
        elif [[ "$line" == *"[INFO]"* ]]; then
            ((info_ref++))
        elif [[ "$line" == *"[WARNING]"* || "$line" == *"[WARN]"* ]]; then
            ((warn_ref++))
        fi
    done < "$result_file"
}

# Function to calculate compliance rate
calculate_compliance_rate() {
    local total="$1"
    local passed="$2"
    local compliance=0
    
    if [ "$total" -gt 0 ]; then
        compliance=$(( (passed * 100) / total ))
    fi
    
    echo "$compliance"
}

# Function to generate section metrics
generate_section_metrics() {
    local section_name="$1"
    local section_total="$2"
    local section_passed="$3"
    local section_failed="$4"
    local section_compliance=0
    
    if [ "$section_total" -gt 0 ]; then
        section_compliance=$(( (section_passed * 100) / section_total ))
    fi
    
    cat << EOF
<div class="section-metrics">
    <div class="metric">
        <span class="label">Total:</span>
        <span class="value">$section_total</span>
    </div>
    <div class="metric pass">
        <span class="label">Passed:</span>
        <span class="value">$section_passed</span>
    </div>
    <div class="metric fail">
        <span class="label">Failed:</span>
        <span class="value">$section_failed</span>
    </div>
    <div class="metric compliance">
        <span class="label">Compliance:</span>
        <span class="value">$section_compliance%</span>
    </div>
</div>
EOF
}

# Main summary generation function
generate_summary() {
    # Initialize variables
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local info_count=0
    local warning_count=0
    
    # Calculate metrics
    calculate_test_metrics "$RESULT_FILE" total_tests passed_tests failed_tests info_count warning_count
    local compliance_rate=$(calculate_compliance_rate "$total_tests" "$passed_tests")
    
    # Log metrics for verification
    {
        echo -e "\nAUDIT SUMMARY REPORT"
        echo "$(printf '=%.0s' {1..80})"
        printf "%-20s: %d\n" "Total Tests" "$total_tests"
        printf "%-20s: %d\n" "Passed Tests" "$passed_tests"
        printf "%-20s: %d\n" "Failed Tests" "$failed_tests"
        printf "%-20s: %d\n" "Info Messages" "$info_count"
        printf "%-20s: %d\n" "Warnings" "$warning_count"
        printf "%-20s: %d%%\n" "Compliance Rate" "$compliance_rate"
        echo -e "\nDetailed results available in: $RESULT_FILE"
    } | tee -a "$RESULT_FILE"
    
    # Generate HTML report
    generate_html_report "$total_tests" "$passed_tests" "$failed_tests" "$compliance_rate" "$info_count" "$warning_count"
}

# Function to generate HTML report
generate_html_report() {
    local total_tests="$1"
    local passed_tests="$2"
    local failed_tests="$3"
    local compliance_rate="$4"
    local info_count="$5"
    local warning_count="$6"
    local report_file="${RESULT_DIR}/${HOSTNAME}_synapxe_rhel8_audit_${TIMESTAMP}.html"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create report directory if it doesn't exist
    mkdir -p "$(dirname "$report_file")" || handle_error "Failed to create report directory" "CRITICAL" "PERMISSION"
    
    # Read HTML template
    if [ ! -f "$HTML_TEMPLATE" ]; then
        handle_error "HTML template not found at $HTML_TEMPLATE" "CRITICAL" "CONFIG"
    fi
    
    # Generate navigation links
    local nav_links=""
    local section_content=""
    local prev_line=""
    
    while IFS= read -r line; do
        if [[ "$line" == *"====="* ]]; then
            # Get section name and create ID
            local section_name=$(echo "$prev_line" | tr -cd '[:alnum:] -')
            local section_id=$(echo "$section_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
            
            # Get emoji based on section name
            local emoji="📋"
            case "$section_name" in
                *"Kernel"*) emoji="💻";;
                *"Network"*) emoji="🌐";;
                *"Security"*) emoji="🔒";;
                *"System"*) emoji="⚙️";;
                *"User"*) emoji="👤";;
                *"File"*) emoji="📁";;
                *"Service"*) emoji="🔧";;
                *"Audit"*) emoji="📝";;
                *"Log"*) emoji="📊";;
            esac
            
            nav_links+="<li><a href=\"#$section_id\"><span class=\"nav-emoji\">$emoji</span> $section_name</a></li>"
            
            # Start new section
            section_content+="<div class=\"section-card\" id=\"$section_id\">"
            section_content+="<h3><span class=\"section-emoji\">$emoji</span> $section_name</h3>"
            
            # Add section metrics
            local section_total=0
            local section_passed=0
            local section_failed=0
            local section_content_buffer=""
            
            # Process section content
            while IFS= read -r content_line; do
                if [[ "$content_line" == *"====="* ]]; then
                    break
                elif [[ "$content_line" == *"[PASS]"* ]]; then
                    ((section_passed++))
                    ((section_total++))
                    section_content_buffer+="<div class=\"result-item pass\"><span class=\"status-icon\">✓</span>$content_line</div>"
                elif [[ "$content_line" == *"[FAIL]"* ]]; then
                    ((section_failed++))
                    ((section_total++))
                    section_content_buffer+="<div class=\"result-item fail\"><span class=\"status-icon\">✗</span>$content_line</div>"
                elif [[ "$content_line" == *"[INFO]"* ]]; then
                    section_content_buffer+="<div class=\"result-item info\"><span class=\"status-icon\">i</span>$content_line</div>"
                elif [[ "$content_line" == *"[WARNING]"* ]]; then
                    section_content_buffer+="<div class=\"result-item warning\"><span class=\"status-icon\">!</span>$content_line</div>"
                fi
            done
            
            # Calculate section compliance rate
            local section_compliance=0
            if [ "$section_total" -gt 0 ]; then
                section_compliance=$(( (section_passed * 100) / section_total ))
            fi
            
            # Add section metrics
            section_content+="<div class=\"section-metrics\">"
            section_content+="<div class=\"metric\"><span class=\"label\">Total:</span><span class=\"value\">$section_total</span></div>"
            section_content+="<div class=\"metric pass\"><span class=\"label\">Passed:</span><span class=\"value\">$section_passed</span></div>"
            section_content+="<div class=\"metric fail\"><span class=\"label\">Failed:</span><span class=\"value\">$section_failed</span></div>"
            section_content+="<div class=\"metric compliance\"><span class=\"label\">Compliance:</span><span class=\"value\">${section_compliance}%</span></div>"
            section_content+="</div>"
            
            # Add section content
            section_content+="$section_content_buffer"
            section_content+="</div>"
        fi
        prev_line="$line"
    done < "$RESULT_FILE"
    
    # Read template and replace placeholders
    local template_content=$(<"$HTML_TEMPLATE")
    
    # Replace placeholders
    template_content=${template_content//__TIMESTAMP__/$timestamp}
    template_content=${template_content//__HOSTNAME__/$HOSTNAME}
    template_content=${template_content//__OS_VERSION__/$OS_VERSION}
    template_content=${template_content//__KERNEL_VERSION__/$KERNEL_VERSION}
    template_content=${template_content//__TOTAL_TESTS__/$total_tests}
    template_content=${template_content//__PASSED_TESTS__/$passed_tests}
    template_content=${template_content//__FAILED_TESTS__/$failed_tests}
    template_content=${template_content//__COMPLIANCE_RATE__/$compliance_rate}
    template_content=${template_content//__INFO_COUNT__/$info_count}
    template_content=${template_content//__WARNING_COUNT__/$warning_count}
    template_content=${template_content//__NAV_LINKS__/$nav_links}
    template_content=${template_content//__SECTION_CONTENT__/$section_content}
    
    # Write report file
    echo "$template_content" > "$report_file"
    
    # Set permissions
    chmod 644 "$report_file" || handle_error "Failed to set report file permissions" "WARNING" "PERMISSION"
    
    log "HTML report generated: $report_file" "INFO"
}

# Main execution
main() {
    # Load configuration
    load_config
    
    # Initialize environment
    init_environment
    
    # Check requirements
    check_requirements
    
    # Backup existing results
    backup_existing_results
    
    # Run audit tests
    run_audit_tests
    
    # Generate summary and report
    generate_summary
}

# Execute main function
main 