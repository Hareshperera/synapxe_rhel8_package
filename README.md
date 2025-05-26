# Synapxe RHEL 8 Audit & Remediation Package

## Contents

- `synapxe_rhel8_audit.sh`: Audit script aligned with Synapxe 2025 CIS RHEL 8 baseline
- `synapxe_rhel8_remediate.sh`: Matching remediation script
- `synapxe_rhel8_audit_coverage_report.csv`: Final compliance comparison report

## Audit Script Usage
### Basic Execution
```bash
chmod +x synapxe_rhel8_audit.sh
./synapxe_rhel8_audit.sh
```
Log file: `/tmp/synapxe_rhel8_audit_results.txt`

### Remediation
```bash
chmod +x synapxe_rhel8_remediate.sh
sudo ./synapxe_rhel8_remediate.sh
```
May require reboot for full effect.

## Notes

- Ensure SSM, sudo privileges, or direct terminal access for execution.
- Scripts designed for Red Hat Enterprise Linux 8 only.

(c) Synapxe 2025 - Security & Compliance
