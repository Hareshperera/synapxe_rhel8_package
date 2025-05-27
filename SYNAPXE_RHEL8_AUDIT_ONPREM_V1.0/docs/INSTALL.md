# Installation Guide

## Prerequisites

- RHEL 8 or compatible system
- Root privileges
- Minimum 500MB free disk space
- Minimum 1GB RAM

## Required Packages

- nftables (>= 0.9.3)
- firewalld (>= 0.8.2)

## Installation Steps

1. Extract the deployment package:
   ```bash
   unzip SYNAPXE_RHEL8_AUDIT_ONPREM_V1.0.zip
   cd SYNAPXE_RHEL8_AUDIT_ONPREM_V1.0
   ```

2. Set up permissions:
   ```bash
   chmod +x bin/*.sh
   chmod 750 bin/
   chmod 640 config/*
   chmod 750 logs/
   chmod 750 backup/
   ```

3. Configure the audit:
   ```bash
   # Review and modify configuration if needed
   vim config/config.conf
   ```

4. Verify installation:
   ```bash
   ./bin/synapxe_rhel8_audit.sh --version
   ```

## Directory Structure

- `bin/`: Executable scripts
- `config/`: Configuration files
- `docs/`: Documentation
- `logs/`: Audit logs
- `backup/`: Backup files
- `templates/`: Report templates
- `scripts/`: Helper scripts
- `tests/`: Test files

## Post-Installation

1. Review the configuration in `config/config.conf`
2. Ensure log directory permissions are correct
3. Test the audit script with `--dry-run` option

## Troubleshooting

Check the following if you encounter issues:
1. File permissions
2. Disk space
3. Package versions
4. Log files in `logs/` directory

## Support

For support, please contact:
- Email: support@synapxe.sg
- Documentation: Refer to `docs/` directory 