# Quick Reference Guide - Synapxe RHEL8 Audit

## Common URLs
- CloudFormation: https://console.aws.amazon.com/cloudformation
- Systems Manager: https://console.aws.amazon.com/systems-manager
- S3: https://console.aws.amazon.com/s3
- CloudWatch: https://console.aws.amazon.com/cloudwatch

## Quick Actions

### Run Manual Audit
1. Systems Manager → Run Command
2. Choose "SynapxeRHEL8Audit"
3. Select targets by OS=RHEL8 tag
4. Run

### View Latest Results
1. S3 → synapxe-rhel8-audit-[ACCOUNT_ID]-[REGION]
2. Sort by date
3. Open newest folder

### Check Status
1. Systems Manager → Run Command
2. Filter by "SynapxeRHEL8Audit"
3. View latest execution

### Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| SSM Agent not running | `sudo systemctl restart amazon-ssm-agent` |
| Missing permissions | Check IAM role `synapxe-rhel8-audit` |
| Failed execution | Check CloudWatch logs in `/aws/ssm/synapxe-rhel8-audit` |
| Missing results | Verify S3 bucket permissions |

### Important Commands

```bash
# Check SSM agent status
sudo systemctl status amazon-ssm-agent

# View SSM logs
tail -f /var/log/amazon/ssm/amazon-ssm-agent.log

# Check audit results directory
ls -la /var/log/synapxe_audit/

# View latest audit results
cat /var/log/synapxe_audit/synapxe_rhel8_audit_results.txt
```

### Support Contacts
- CPE Team: [Contact Information]
- AWS Support: Through AWS Console
- Emergency: [Emergency Contact] 