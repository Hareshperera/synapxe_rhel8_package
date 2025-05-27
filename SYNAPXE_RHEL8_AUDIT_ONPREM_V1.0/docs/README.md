# Synapxe RHEL8 Audit Package

A comprehensive audit package for RHEL 8 systems based on CIS Baseline 2025.

## Features

- **Comprehensive System Audit**: Checks system configuration against CIS Baseline 2025 recommendations
- **Beautiful HTML Reports**: Modern, responsive reports with:
  - Interactive dashboard with key metrics
  - Section-by-section compliance rates
  - Easy navigation with sticky menu
  - Visual indicators for test results
  - Mobile-friendly design
- **Enhanced Error Handling**: Robust error handling with:
  - Detailed error messages
  - Error tracking and logging
  - Graceful recovery options
- **Configuration Management**: Centralized configuration for:
  - System requirements
  - Package versions
  - Test parameters
  - Report styling
  - Security settings

## Directory Structure

```
.
├── README.md
├── onprem_v2/
│   ├── config/
│   │   ├── config.conf         # Main configuration file
│   │   └── report_template.html # HTML report template
│   ├── synapxe_rhel8_audit.sh  # Main audit script
│   └── synapxe_rhel8_remediate.sh # Remediation script
```

## Requirements

- RHEL 8 or compatible system
- Root privileges
- Required packages:
  - nftables (>= 0.9.3)
  - firewalld (>= 0.8.2)
- Minimum 500MB free disk space
- Minimum 1GB RAM

## Installation

1. Clone the repository:
   ```bash
   git clone <repository_url>
   cd synapxe_rhel8_package
   ```

2. Make scripts executable:
   ```bash
   chmod +x onprem_v2/*.sh
   ```

3. Review and adjust configuration:
   ```bash
   vim onprem_v2/config/config.conf
   ```

## Usage

1. Run the audit:
   ```bash
   sudo ./onprem_v2/synapxe_rhel8_audit.sh
   ```

2. View the report:
   The HTML report will be generated at `/var/log/synapxe_audit/<hostname>_synapxe_rhel8_audit_<timestamp>.html`

3. Optional: Run remediation:
   ```bash
   sudo ./onprem_v2/synapxe_rhel8_remediate.sh
   ```

## Report Features

- **Summary Dashboard**:
  - Total tests run
  - Passed/failed tests
  - Overall compliance rate
  - Info and warning counts

- **Section Navigation**:
  - Quick links to each section
  - Visual indicators for section status
  - Smooth scrolling

- **Test Results**:
  - Clear pass/fail indicators
  - Detailed test descriptions
  - Section-specific compliance rates

- **Responsive Design**:
  - Works on desktop and mobile
  - Adjusts layout for screen size
  - Touch-friendly navigation

## Configuration

The `config.conf` file allows customization of:

- System requirements
- Package versions
- Test parameters
- Report styling
- Security settings

Example configuration:
```bash
# System Requirements
MIN_DISK_SPACE=500000  # 500MB in KB
REQUIRED_MEMORY=1024   # 1GB in MB

# Report Configuration
REPORT_STYLE="modern"
INCLUDE_TRENDS=true
INCLUDE_REMEDIATION=true
```

## Error Handling

The script includes comprehensive error handling:

- Error codes for different types of issues
- Detailed error messages
- Error logging to syslog
- Recovery mechanisms
- Incomplete run handling

## Security Features

- Secure file permissions
- Error tracking
- Audit logging
- Backup of results
- Clean error handling

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Authors

- CPE Team
- Synapxe Development Team 