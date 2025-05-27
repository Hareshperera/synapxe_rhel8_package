# Synapxe RHEL8 Audit - AWS Implementation

This directory contains the AWS implementation of the Synapxe RHEL8 Audit system.

## Directory Structure

```
aws/
├── cloudformation/
│   ├── templates/          # CloudFormation templates
│   │   └── synapxe_rhel8_ssm.yaml
│   └── parameters/         # Environment-specific parameters
├── scripts/               # Audit and utility scripts
│   └── synapxe_rhel8_audit.sh
└── docs/                 # Documentation
    └── README.md
```

## Implementation Details

### CloudFormation Stack

The `synapxe_rhel8_ssm.yaml` template creates:
- S3 bucket for audit results with encryption
- KMS key for data encryption
- IAM roles and policies
- SSM automation document
- EventBridge scheduled rule
- SNS topic for notifications

### Security Features

1. Data Protection:
   - S3 bucket encryption with AES-256
   - KMS key for additional encryption
   - No public access to S3 bucket
   - Versioning enabled

2. Access Control:
   - IAM roles with least privilege
   - SSM managed instance core permissions
   - Restricted KMS key usage

3. Audit Trail:
   - Results stored with instance metadata
   - Timestamp-based organization
   - Automated cleanup of old files

## Deployment

1. Prerequisites:
   ```bash
   # Tag RHEL8 instances
   aws ec2 create-tags --resources i-1234567890abcdef0 --tags Key=OS,Value=RHEL8
   ```

2. Deploy the stack:
   ```bash
   aws cloudformation create-stack \
     --stack-name synapxe-rhel8-audit \
     --template-body file://cloudformation/templates/synapxe_rhel8_ssm.yaml \
     --capabilities CAPABILITY_IAM \
     --parameters \
       ParameterKey=ScheduleExpression,ParameterValue="rate(7 days)" \
       ParameterKey=TargetEnvironment,ParameterValue=Production
   ```

3. Verify deployment:
   ```bash
   aws cloudformation describe-stacks --stack-name synapxe-rhel8-audit
   ```

## Monitoring

1. View audit results:
   ```bash
   aws s3 ls s3://synapxe-rhel8-audit-${ACCOUNT_ID}-${REGION}/results/
   ```

2. Check SSM execution status:
   ```bash
   aws ssm list-command-invocations --filters Key=DocumentName,Values=SynapxeRHEL8Audit
   ```

3. Monitor notifications:
   ```bash
   aws sns list-subscriptions-by-topic --topic-arn ${SNS_TOPIC_ARN}
   ```

## Maintenance

1. Update audit schedule:
   ```bash
   aws cloudformation update-stack \
     --stack-name synapxe-rhel8-audit \
     --use-previous-template \
     --parameters \
       ParameterKey=ScheduleExpression,ParameterValue="rate(1 day)"
   ```

2. Manage audit results:
   - Results are automatically archived to STANDARD_IA after 90 days
   - Results are automatically deleted after 365 days
   - Manual cleanup if needed:
     ```bash
     aws s3 rm s3://synapxe-rhel8-audit-${ACCOUNT_ID}-${REGION}/results/ --recursive
     ```

## Support

For issues or questions:
1. Check CloudWatch Logs for execution details
2. Verify instance tags and IAM roles
3. Ensure SSM agent is running on target instances
4. Contact the CPE team for additional support 