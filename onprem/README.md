# Synapxe RHEL 8 Audit & Remediation Package

## Overview

This package provides comprehensive security audit and remediation tools for Red Hat Enterprise Linux 8 systems, aligned with Synapxe 2025 CIS baseline requirements.

## Contents

- `synapxe_rhel8_audit.sh`: Security audit script
- `synapxe_rhel8_remediate.sh`: Remediation script
- `synapxe_rhel8_audit_coverage_report.csv`: Compliance report

## Features

- Security checks across domains
- JSON/HTML/text output reports
- Automated remediation with rollback
- Resource usage tracking
- Logging and categorization

## Requirements

### System Requirements
- RHEL 8.x (Red Hat Enterprise Linux 8) only
- Bash 4.2 or higher
- 2+ CPU cores
- 2GB+ RAM

### Required Commands
The following commands must be available on the system:
- rpm
- systemctl
- grep
- awk
- stat
- sysctl
- nft (nftables)
- firewall-cmd

### Permissions
- Root access or sudo privileges required
- SSM access for system modifications

## Usage

### Pre-flight Checks
1. Verify you are on a RHEL 8 system
2. Ensure all required commands are installed
3. Verify root/sudo access

### Running the Audit
```bash
chmod +x synapxe_rhel8_audit.sh
sudo ./synapxe_rhel8_audit.sh
```

Remediation:
chmod +x synapxe_rhel8_remediate.sh
sudo ./synapxe_rhel8_remediate.sh

Requirements

RHEL 8.x with Bash 4.2+

2+ CPU cores, 2GB+ RAM

Sudo or SSM access

Support

Collect logs and system info

Run in test before production

License

(c) Synapxe 2025 - Security & Compliance. All rights reserved.