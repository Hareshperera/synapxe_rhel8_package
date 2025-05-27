# Synapxe RHEL8 Audit Package

This package provides comprehensive security audit tools for Red Hat Enterprise Linux 8 systems, with support for both AWS cloud deployment and on-premises server deployment.

## Deployment Options

### 1. AWS Cloud Deployment (`aws/`)

The AWS deployment option provides a fully managed, cloud-native implementation with:

- **Infrastructure as Code**
  - CloudFormation templates for automated setup
  - Systems Manager (SSM) for audit automation
  - S3 buckets for secure result storage
  - EventBridge for scheduled executions
  - SNS for notifications and alerts

- **Security Features**
  - IAM role-based access control
  - Encrypted audit storage
  - Audit trail and logging
  - Compliance reporting

For AWS deployment instructions and documentation, see:
- `aws/docs/CONSOLE_SECURITY.md` for security setup
- `aws/docs/templates/` for change management
- `aws/cloudformation/` for infrastructure templates

### 2. On-Premises Deployment (`onprem/`)

The on-premises deployment option provides direct server execution with:

- **Direct System Access**
  - Local script execution
  - System-level auditing
  - Local result storage
  - Manual or cron-based scheduling

- **Features**
  - Comprehensive security checks
  - Multiple output formats (JSON/HTML/text)
  - Automated remediation options
  - Resource usage monitoring

For on-premises deployment instructions and documentation, see:
- `onprem/README.md` for setup and usage
- `onprem/synapxe_rhel8_audit.sh` for the main audit script
- `onprem/synapxe_rhel8_remediate.sh` for remediation

## System Requirements

### AWS Deployment
- AWS Account with required permissions
- RHEL 8.x instances
- IAM roles and policies
- Network access to AWS services

### On-Premises Deployment
- RHEL 8.x
- Bash 4.2 or higher
- 2+ CPU cores
- 2GB+ RAM
- Root/sudo access

## Support

For deployment-specific support:

- **AWS Issues**: 
  1. Check CloudWatch logs
  2. Review AWS service status
  3. Verify IAM permissions
  4. Contact AWS support if needed

- **On-Premises Issues**:
  1. Check system logs
  2. Verify system requirements
  3. Review script output
  4. Contact system administrators

## License

(c) Synapxe 2025 - Security & Compliance. All rights reserved. 