# AWS Console Guide - Synapxe RHEL8 Audit

This guide provides step-by-step instructions for deploying and running the Synapxe RHEL8 Audit using the AWS Console.

## 1. Deploy CloudFormation Stack

### Step 1: Navigate to CloudFormation
1. Log in to AWS Console
2. Go to Services → CloudFormation
3. Click "Create stack" → "With new resources (standard)"

### Step 2: Upload Template
1. Select "Upload a template file"
2. Click "Choose file"
3. Navigate to `aws/cloudformation/templates/synapxe_rhel8_ssm.yaml`
4. Click "Next"

### Step 3: Configure Stack
1. Enter Stack name: `synapxe-rhel8-audit`
2. Configure Parameters:
   - ScheduleExpression: `rate(7 days)` (or your preferred schedule)
   - TargetEnvironment: Select `Production` (or your target environment)
3. Click "Next"

### Step 4: Configure Stack Options
1. Tags (Optional):
   - Key: `Project`
   - Value: `Synapxe-RHEL8-Audit`
2. Permissions: Use the default role
3. Click "Next"

### Step 5: Review and Create
1. Review all settings
2. Check the acknowledgment for IAM resource creation
3. Click "Create stack"

## 2. Tag RHEL8 Instances

### Step 1: Navigate to EC2
1. Go to Services → EC2
2. Click "Instances"

### Step 2: Tag Instances
1. Select your RHEL8 instances
2. Click "Actions" → "Tags" → "Add/Edit tags"
3. Add tag:
   - Key: `OS`
   - Value: `RHEL8`
4. Click "Save"

## 3. Run Manual Audit (Optional)

### Step 1: Navigate to Systems Manager
1. Go to Services → Systems Manager
2. Click "Documents" in the left sidebar

### Step 2: Find the Audit Document
1. Switch to "Owned by me" tab
2. Search for "SynapxeRHEL8Audit"
3. Select the document

### Step 3: Execute Audit
1. Click "Run command"
2. Target selection:
   - Choose "Specify tags"
   - Add tag:
     - Key: `OS`
     - Value: `RHEL8`
3. Parameters:
   - Environment: Select your environment
   - OutputBucket: Use the created S3 bucket name
   - KMSKeyId: Use the created KMS key ID
4. Output options:
   - Enable CloudWatch logs
   - Enable S3 logging
5. Click "Run"

## 4. View Results

### Step 1: Check Execution Status
1. Go to Systems Manager → Run Command
2. Find your command execution
3. Check the status and output

### Step 2: View Audit Results
1. Go to Services → S3
2. Navigate to bucket `synapxe-rhel8-audit-[ACCOUNT_ID]-[REGION]`
3. Browse to `results/[INSTANCE_ID]/[TIMESTAMP]/`
4. Download and view:
   - `audit_results.txt` for detailed results
   - `audit_results.html` for formatted report

### Step 3: Monitor Notifications
1. Go to Services → SNS
2. Click "Topics"
3. Select `synapxe-rhel8-audit-notifications-[REGION]`
4. View subscriptions and notifications

## 5. Troubleshooting

### Check SSM Agent Status
1. Connect to your instance
2. Run: `systemctl status amazon-ssm-agent`
3. Check logs: `tail -f /var/log/amazon/ssm/amazon-ssm-agent.log`

### Verify IAM Roles
1. Go to Services → IAM
2. Click "Roles"
3. Search for `synapxe-rhel8-audit`
4. Verify permissions

### Check CloudWatch Logs
1. Go to Services → CloudWatch
2. Click "Log groups"
3. Find `/aws/ssm/synapxe-rhel8-audit`
4. View execution logs

## 6. Maintenance Tasks

### Update Schedule
1. Go to Services → CloudFormation
2. Select your stack
3. Click "Update"
4. Choose "Use current template"
5. Modify ScheduleExpression parameter
6. Complete the update wizard

### Manage Results
1. Go to Services → S3
2. Navigate to your audit bucket
3. Use lifecycle rules for:
   - Archiving (after 90 days)
   - Deletion (after 365 days)

## Support and Resources

### Documentation
- AWS Systems Manager Documentation
- CloudFormation Documentation
- S3 Documentation

### Contact Support
1. Check CloudWatch Logs for errors
2. Verify instance configuration
3. Contact CPE team with:
   - Instance ID
   - Error messages
   - CloudWatch logs
   - Execution time 