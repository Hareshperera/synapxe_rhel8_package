# AWS Console Security Guide - Synapxe RHEL8 Audit

## Console Access Security

### 1. IAM User Setup
1. Go to IAM → Users
2. Ensure users have:
   - Strong password policy
   - MFA enabled
   - No programmatic access keys
   - Console-only access

### 2. Required IAM Permissions
Minimum required permissions for audit management:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:Describe*",
                "cloudformation:List*",
                "cloudformation:Get*",
                "s3:GetObject",
                "s3:ListBucket",
                "ssm:DescribeDocument",
                "ssm:GetDocument",
                "ssm:ListDocuments",
                "ssm:DescribeInstanceInformation",
                "ec2:DescribeInstances",
                "sns:ListSubscriptions",
                "cloudwatch:GetMetricData",
                "cloudwatch:GetMetricStatistics"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::synapxe-rhel8-audit-*",
                "arn:aws:s3:::synapxe-rhel8-audit-*/*"
            ]
        }
    ]
}
```

### 3. Security Best Practices

#### Session Management
1. Maximum session duration: 8 hours
2. Automatic session timeout: 15 minutes
3. Force sign-out when password changes

#### Access Controls
1. IP restriction for console access
2. Require MFA for all actions
3. No sharing of credentials

### 4. Monitoring Setup

#### CloudWatch Alarms
1. Navigate to CloudWatch → Alarms
2. Create alarms for:
   - Failed audit runs
   - Missing scheduled audits
   - Unauthorized access attempts

#### SNS Notifications
1. Go to SNS → Topics
2. Subscribe security team email
3. Enable notifications for:
   - Audit completion
   - Security findings
   - Permission changes

### 5. Audit Results Security

#### S3 Bucket Access
1. Go to S3 → synapxe-rhel8-audit bucket
2. Verify bucket policy:
   - Block public access
   - Enforce encryption
   - Require HTTPS
   - Enable versioning

#### KMS Key Management
1. Navigate to KMS → Customer managed keys
2. Review key policies:
   - Key administrators
   - Key users
   - Key rotation

### 6. Emergency Procedures

#### Access Issues
1. Contact Security Team Lead
2. Use emergency access procedure
3. Document all emergency access

#### Failed Audits
1. Check instance status
2. Verify SSM agent
3. Review CloudWatch logs
4. Escalate to security team

### 7. Regular Maintenance

#### Weekly Tasks
1. Review audit results
2. Check failed executions
3. Verify instance tags
4. Monitor storage usage

#### Monthly Tasks
1. Review IAM permissions
2. Check notification subscriptions
3. Validate backup retention
4. Update documentation

### 8. Compliance Documentation

#### Required Screenshots
1. Audit results page
2. CloudWatch metrics
3. Instance compliance status
4. Error logs (if any)

#### Report Generation
1. Navigate to S3 bucket
2. Download latest audit reports
3. Generate compliance summary
4. Archive previous reports

### 9. Instance Management

#### Tag Management
1. Go to EC2 → Instances
2. Verify required tags:
   - OS=RHEL8
   - Environment
   - Application
   - Owner

#### Health Checks
1. Check SSM agent status
2. Verify instance connectivity
3. Monitor system resources
4. Review audit logs

### 10. Troubleshooting Guide

#### Common Issues

| Issue | Console Check | Resolution |
|-------|--------------|------------|
| Missing Results | S3 Bucket → Latest folder | Check instance tags |
| Failed Audit | Systems Manager → Run Command | Verify instance status |
| Permission Error | IAM → Roles | Review role permissions |
| Notification Failure | SNS → Topics | Check subscriptions |

#### Resolution Steps
1. Check instance health in EC2 console
2. Review CloudWatch logs
3. Verify security group rules
4. Validate IAM permissions

### 11. Change Management

#### Making Changes
1. Document proposed change
2. Get security team approval
3. Schedule maintenance window
4. Execute in console
5. Verify changes
6. Update documentation

#### Rollback Procedure
1. Document current state
2. Take screenshots
3. Make changes
4. Verify functionality
5. Document results

### 12. Support Process

#### Level 1 Support
1. Check basic connectivity
2. Verify instance status
3. Review recent changes
4. Document findings

#### Level 2 Support
1. Deep dive CloudWatch logs
2. Review IAM permissions
3. Check network config
4. Analyze audit results

#### Escalation Path
1. Team Lead
2. Security Team
3. AWS Support (if needed)
4. Emergency Contact 