# Security Policy

## Overview

This document outlines the security practices, threat model, and vulnerability reporting procedures for the AWS Multi-Region Warm Standby DR project.

## Supported Versions

| Version | Supported          | Security Updates |
| ------- | ------------------ | ---------------- |
| 2.0.x   | :white_check_mark: | Active           |
| 1.0.x   | :white_check_mark: | Critical only    |
| < 1.0   | :x:                | Not supported    |

## Security Architecture

### Defense in Depth

This project implements multiple layers of security:

```
┌─────────────────────────────────────────┐
│ 1. Network Layer                        │
│    - VPC isolation                      │
│    - Public/Private subnet segregation  │
│    - Security groups (stateful firewall)│
│    - NACLs (stateless firewall)        │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│ 2. Compute Layer                        │
│    - Private subnets for EC2            │
│    - IMDSv2 enforced                    │
│    - Systems Manager Session Manager   │
│    - No SSH keys in production          │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│ 3. Data Layer                           │
│    - RDS encryption at rest (KMS)       │
│    - RDS encryption in transit (TLS)    │
│    - Automated backups                  │
│    - Database subnet group isolation    │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│ 4. Access Control                       │
│    - IAM roles (no long-term keys)      │
│    - Least privilege principle          │
│    - MFA for human access               │
│    - Service Control Policies (SCPs)    │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│ 5. Monitoring & Logging                 │
│    - VPC Flow Logs                      │
│    - CloudTrail (API logging)           │
│    - CloudWatch Logs                    │
│    - GuardDuty (threat detection)       │
└─────────────────────────────────────────┘
```

## Security Best Practices

### Before Deployment

#### 1. Credentials Management

**❌ DO NOT**:
- Hardcode credentials in Terraform files
- Commit `terraform.tfvars` to git
- Use default passwords in production
- Store secrets in plain text

**✅ DO**:
```hcl
# Use AWS Secrets Manager
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/database/password"
}

# Or use environment variables
export TF_VAR_db_password="your-secure-password"
terraform apply
```

#### 2. State File Security

**Terraform state contains sensitive data**. Secure it:

```hcl
# backend.tf (create this file)
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "warm-standby-dr/terraform.tfstate"
    region         = "af-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    kms_key_id     = "arn:aws:kms:af-south-1:ACCOUNT:key/KEY-ID"
  }
}
```

**Enable**:
- S3 bucket versioning
- S3 bucket encryption (SSE-KMS)
- S3 bucket access logging
- DynamoDB table for state locking

#### 3. IAM Permissions

**Minimum required permissions** for deployment:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "rds:*",
        "route53:*",
        "s3:*",
        "cloudwatch:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

**Production recommendation**: Use AWS Organizations SCPs to restrict:
- Approved regions only (af-south-1, eu-west-1)
- Approved instance types only
- Require encryption for all storage
- Prevent CloudTrail deletion

### Network Security

#### Security Group Rules

**ALB Security Group** (Public):
```hcl
# Ingress
HTTPS (443) from 0.0.0.0/0    # Internet traffic
HTTP  (80)  from 0.0.0.0/0    # Redirect to HTTPS

# Egress
All traffic to Application SG  # Forward to instances
```

**Application Security Group** (Private):
```hcl
# Ingress
HTTP (8080) from ALB SG only   # Only ALB can reach instances

# Egress
HTTPS (443) to 0.0.0.0/0      # Updates, package downloads
PostgreSQL (5432) to RDS SG    # Database access
```

**RDS Security Group** (Private):
```hcl
# Ingress
MySQL (3306) from Application SG only  # Only app tier access

# Egress
None required
```

#### Network ACLs

Default VPC NACLs allow all traffic. For production, implement explicit rules:

```hcl
# Public subnet NACL
Inbound:  80/443 from 0.0.0.0/0       # Web traffic
Inbound:  1024-65535 from 0.0.0.0/0   # Return traffic
Outbound: All allowed

# Private subnet NACL
Inbound:  8080 from 10.0.0.0/16       # From ALB
Inbound:  1024-65535 from 0.0.0.0/0   # Return traffic
Outbound: All allowed
```

### Data Security

#### Encryption at Rest

**Enabled by default**:
- ✅ RDS storage encryption (KMS)
- ✅ EBS volume encryption
- ✅ S3 bucket encryption

**Verify encryption**:
```bash
# Check RDS encryption
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,StorageEncrypted]'

# Check S3 encryption
aws s3api get-bucket-encryption --bucket your-bucket-name
```

#### Encryption in Transit

**Enforced**:
- ✅ ALB → EC2: HTTPS
- ✅ EC2 → RDS: TLS 1.2+
- ✅ S3 replication: TLS 1.2+

**Enforce TLS on RDS**:
```sql
-- Require TLS for MySQL connections
GRANT USAGE ON *.* TO 'appuser'@'%' REQUIRE SSL;
```

### Access Control

#### IAM Roles (Recommended)

**For EC2 instances**:
```hcl
# Attach IAM role, not access keys
resource "aws_iam_instance_profile" "app_profile" {
  name = "app-instance-profile"
  role = aws_iam_role.app_role.name
}

# EC2 uses role to access S3, Secrets Manager, etc.
# No access keys needed
```

#### SSH Access (NOT Recommended)

**Avoid SSH keys**. Use AWS Systems Manager Session Manager instead:

```bash
# Connect without SSH keys
aws ssm start-session --target i-1234567890abcdef0
```

**Benefits**:
- No open port 22
- No SSH key management
- All sessions logged in CloudTrail
- MFA enforcement possible

If SSH is required:
- Use bastion host in public subnet
- Restrict SSH to corporate IP ranges
- Rotate keys regularly
- Use ED25519 keys (not RSA 2048)

### Monitoring and Detection

#### Enable Logging

**Required**:
```hcl
# VPC Flow Logs
resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
}

# CloudTrail (API logging)
resource "aws_cloudtrail" "main" {
  name                          = "security-audit-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true  # Tamper detection
}
```

#### Enable GuardDuty

```bash
# Enable threat detection
aws guardduty create-detector --enable --region af-south-1
aws guardduty create-detector --enable --region eu-west-1
```

**Monitors for**:
- Compromised instances (crypto mining, C&C communication)
- Unusual API calls
- Unauthorized access attempts
- Port scanning activity

#### CloudWatch Alarms

**Critical security alarms**:

```hcl
# Root account usage
resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "root-account-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootAccountUsage"
  threshold           = "0"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

# Unauthorized API calls
resource "aws_cloudwatch_metric_alarm" "unauthorized_calls" {
  alarm_name          = "unauthorized-api-calls"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedAPICalls"
  threshold           = "5"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}
```

## Threat Model

### Threats Mitigated

| Threat | Mitigation | Residual Risk |
|--------|-----------|---------------|
| **DDoS attack** | AWS Shield Standard, CloudFront, ALB auto scaling | Medium - need Shield Advanced for large attacks |
| **Data breach** | Encryption at rest/transit, private subnets, security groups | Low |
| **Compromised credentials** | IAM roles, no long-term keys, MFA | Low |
| **Insider threat** | CloudTrail logging, least privilege IAM | Medium - requires process controls |
| **SQL injection** | Parameterized queries, WAF (recommended) | Medium - application-level concern |
| **Region failure** | Multi-region DR, automatic failover | Low |

### Threats NOT Mitigated

- **Application vulnerabilities**: Requires secure coding practices
- **Social engineering**: Requires security awareness training
- **Supply chain attacks**: Requires dependency scanning
- **Advanced persistent threats**: Requires security operations center (SOC)

## Vulnerability Reporting

### Reporting a Vulnerability

If you discover a security vulnerability, please follow responsible disclosure:

**DO**:
1. Email security concerns to: [your-security-email@domain.com]
2. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested remediation (if known)
3. Allow 90 days for remediation before public disclosure
4. Coordinate disclosure timeline with maintainer

**DO NOT**:
- Open a public GitHub issue for security vulnerabilities
- Exploit the vulnerability beyond proof-of-concept
- Publicly disclose before maintainer confirmation

### Response Timeline

- **Initial response**: Within 48 hours
- **Severity assessment**: Within 5 business days
- **Fix timeline**:
  - Critical: 7 days
  - High: 30 days
  - Medium: 60 days
  - Low: 90 days

### Security Advisories

Security fixes will be announced via:
- GitHub Security Advisories
- CHANGELOG.md (Security section)
- Git tags (e.g., `v2.0.1-security`)

## Compliance

### Standards Alignment

This architecture supports:

- **ISO 27001**: Information security management
  - Access controls (IAM, security groups)
  - Encryption (data at rest and in transit)
  - Logging and monitoring (CloudTrail, CloudWatch)
  - Incident response (GuardDuty, alarms)

- **SOC 2 Type II**: Security, availability, confidentiality
  - Multi-AZ deployment (availability)
  - Disaster recovery (business continuity)
  - Encryption (confidentiality)
  - Audit logging (accountability)

- **POPIA** (South Africa): Personal data protection
  - Data residency (af-south-1 primary)
  - Encryption (data protection)
  - Access controls (data subject rights)
  - Audit trail (accountability)

- **GDPR** (European Union): Data protection
  - Data residency (eu-west-1 DR)
  - Encryption (security of processing)
  - Access controls (data minimization)
  - Right to be forgotten (data lifecycle)

### Audit Readiness

**Evidence for auditors**:
- CloudTrail logs (90-day retention minimum)
- VPC Flow Logs (network activity)
- AWS Config (configuration history)
- This SECURITY.md document
- CHANGELOG.md (change management)

## Security Checklist

### Pre-Deployment

- [ ] Change default database password
- [ ] Configure remote state with encryption
- [ ] Review IAM permissions (least privilege)
- [ ] Add `.gitignore` for `terraform.tfvars`
- [ ] Enable MFA on AWS account
- [ ] Review security group rules
- [ ] Plan IP whitelist for administrative access

### Post-Deployment

- [ ] Enable GuardDuty in both regions
- [ ] Configure CloudWatch security alarms
- [ ] Enable CloudTrail in all regions
- [ ] Enable VPC Flow Logs
- [ ] Test SSH/Session Manager access
- [ ] Verify encryption on RDS and S3
- [ ] Configure SNS topic for security alerts
- [ ] Document access procedures
- [ ] Schedule security review (quarterly)

### Ongoing

- [ ] Rotate IAM credentials (90 days)
- [ ] Review security group rules (monthly)
- [ ] Review CloudTrail logs (weekly)
- [ ] Update Terraform and provider versions (monthly)
- [ ] Review GuardDuty findings (daily)
- [ ] Test DR failover (quarterly)
- [ ] Security awareness training (annually)

## References

- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [AWS Well-Architected Framework - Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

---

**Last Updated**: 2026-05-15  
**Version**: 2.0.0
