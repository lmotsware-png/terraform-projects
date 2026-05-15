# AWS Multi-Region Warm Standby Disaster Recovery

Enterprise-grade disaster recovery architecture implementing warm standby failover across AWS regions using Infrastructure as Code.

[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazon-aws)](https://aws.amazon.com/)


## Architecture Overview

This project demonstrates a production-ready disaster recovery solution with automatic failover between AWS regions:

- **Primary Region**: `af-south-1` (Cape Town) - Full production capacity
- **DR Region**: `eu-west-1` (Ireland) - Warm standby at 20% capacity
- **RTO**: 15 minutes (Recovery Time Objective)
- **RPO**: 5 minutes (Recovery Point Objective)
- **Failover**: Automatic DNS-based switching via Route 53

## Infrastructure Components

### Primary Region (Cape Town)

```
VPC (10.0.0.0/16)
├── Public Subnets (2 AZs)
│   └── Application Load Balancer
├── Private Subnets (2 AZs)
│   ├── Auto Scaling Group (2-10 instances)
│   │   └── t3.medium instances
│   └── RDS Aurora MySQL Multi-AZ
│       └── Primary database cluster
└── NAT Gateways (2 AZs for high availability)
```

### DR Region (Ireland)

```
VPC (10.1.0.0/16)
├── Public Subnets (2 AZs)
│   └── Application Load Balancer (standby)
├── Private Subnets (2 AZs)
│   ├── Auto Scaling Group (1-3 instances)
│   │   └── t3.small instances (scaled down)
│   └── RDS Aurora Read Replica
│       └── Continuous replication from primary
└── NAT Gateways (2 AZs)
```

### Disaster Recovery Features

- **RDS Cross-Region Replication**: Asynchronous replication with <5 minute lag
- **S3 Cross-Region Replication**: Automatic object replication for static assets
- **Route 53 Health Checks**: Active monitoring with 30-second intervals
- **Automatic Failover**: DNS switches to DR region if primary health check fails
- **Auto Scaling**: DR region scales from 20% to 100% capacity on failover

## Technical Specifications

| Component | Primary Region | DR Region | Failover Trigger |
|-----------|---------------|-----------|------------------|
| **Compute** | 2-10 t3.medium | 1-3 t3.small | Auto scales on traffic |
| **Database** | RDS Multi-AZ Primary | Read Replica | Manual promotion |
| **Load Balancer** | Active | Standby | Route 53 health check |
| **DNS TTL** | 60 seconds | 60 seconds | Automatic switch |
| **Health Check** | 30s interval | 30s interval | 3 consecutive failures |

## Deployment

### Prerequisites

- **Terraform**: v1.0+ installed
- **AWS CLI**: Configured with appropriate credentials
- **IAM Permissions**: Full access to VPC, EC2, RDS, Route 53, S3
- **Domain**: Registered domain for Route 53 hosted zone

### Configuration

1. **Clone the repository**:
   ```bash
   git clone https://github.com/lmotsware-png/terraform-projects.git
   cd terraform-projects/warm-standby-dr
   ```

2. **Configure variables** in `terraform.tfvars`:
   ```hcl
   project_name = "your-project"
   environment  = "production"
   
   # Database credentials
   db_username = "admin"
   db_password = "YourSecurePassword123!"  # Change this!
   
   # DNS configuration
   domain_name = "yourdomain.com"
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Review the plan**:
   ```bash
   terraform plan
   ```

5. **Deploy infrastructure**:
   ```bash
   terraform apply
   ```

### Deployment Time

- **Initial deployment**: ~20 minutes
- **RDS cluster creation**: ~10-15 minutes
- **Read replica setup**: ~5-10 minutes
- **Total**: ~30-35 minutes

## Failover Testing

### Simulate Primary Region Failure

```bash
# Stop primary ALB health checks
aws elbv2 modify-target-group \
  --target-group-arn <primary-tg-arn> \
  --health-check-enabled false \
  --region af-south-1

# Monitor Route 53 failover (occurs within 90 seconds)
watch -n 5 'dig +short yourdomain.com'
```

### Promote Read Replica (Manual Step)

```bash
# After DNS failover, promote read replica to primary
aws rds promote-read-replica \
  --db-instance-identifier dr-replica \
  --region eu-west-1
```

### Restore Primary Region

```bash
# Re-enable health checks
aws elbv2 modify-target-group \
  --target-group-arn <primary-tg-arn> \
  --health-check-enabled true \
  --region af-south-1

# Traffic automatically fails back within 90 seconds
```

## Cost Optimization

### Monthly Cost Estimate (USD)

| Resource | Primary | DR | Total |
|----------|---------|-----|-------|
| EC2 (t3.medium/small) | $140 | $35 | $175 |
| RDS Aurora (Multi-AZ + replica) | $290 | $145 | $435 |
| ALB (2 regions) | $32 | $32 | $64 |
| NAT Gateways (4 total) | $90 | $90 | $180 |
| Data Transfer | $50 | $25 | $75 |
| Route 53 | - | - | $1 |
| **Monthly Total** | - | - | **~$930** |

### Cost Reduction Strategies

- Use Reserved Instances for baseline capacity (40% savings)
- Scale DR region to minimum until failover needed
- Use S3 Intelligent-Tiering for replicated objects
- Leverage Savings Plans for consistent usage

## Security

This project implements AWS security best practices:

- ✅ All traffic encrypted in transit (TLS 1.2+)
- ✅ Database encryption at rest with AWS KMS
- ✅ Private subnets for compute and database layers
- ✅ Security groups follow least privilege principle
- ✅ No hardcoded credentials (use AWS Secrets Manager in production)
- ✅ VPC Flow Logs enabled for network monitoring
- ✅ CloudTrail logging for audit trail

**⚠️ Important**: Change default database password in `terraform.tfvars` before deployment.

See [SECURITY.md](SECURITY.md) for detailed security practices.

## Monitoring and Alerts

### CloudWatch Metrics Tracked

- ALB healthy target count
- RDS CPU utilization and connections
- Auto Scaling Group desired/actual capacity
- Route 53 health check status
- Cross-region replication lag

### Recommended Alarms

```hcl
# Primary region unhealthy targets
Metric: HealthyHostCount
Threshold: < 1
Action: SNS notification to ops team

# RDS replication lag
Metric: AuroraReplicaLag
Threshold: > 300 seconds (5 minutes)
Action: Alert database team

# DR region auto scaling
Metric: GroupDesiredCapacity
Threshold: > 1 (indicates failover)
Action: Alert on-call engineer
```

## Project Structure

```
warm-standby-dr/
├── README.md           # This file
├── CHANGELOG.md        # Version history
├── SECURITY.md         # Security best practices
├── providers.tf        # AWS provider configuration (dual-region)
├── variables.tf        # Input variables and defaults
├── main-region.tf      # Primary region infrastructure (Cape Town)
├── dr-region.tf        # DR region infrastructure (Ireland)
├── database.tf         # RDS primary and read replica setup
├── route53.tf          # DNS failover configuration
└── terraform.tfvars    # User-specific variable values (not in git)
```

## Design Decisions

### Why Warm Standby?

| DR Strategy | RTO | RPO | Cost | Use Case |
|-------------|-----|-----|------|----------|
| Backup/Restore | Hours | Hours | Low | Non-critical systems |
| Pilot Light | 30-60 min | 15 min | Medium | Cost-sensitive |
| **Warm Standby** | **15 min** | **5 min** | **Medium-High** | **Production apps** ✅ |
| Hot/Hot Active | Minutes | Seconds | High | Critical systems |

**Warm Standby selected for**: Balance between cost and recovery speed suitable for production business applications.

### Why These Regions?

- **Cape Town (af-south-1)**: Primary for South African data residency requirements
- **Ireland (eu-west-1)**: Geographically distant, low latency to Europe/Africa, mature region with all services

### Why Route 53 Health Checks?

- Native AWS integration with ALB
- Sub-minute detection of failures
- Automatic DNS propagation
- No additional infrastructure needed

## Known Limitations

- RDS read replica promotion is **manual** (requires ~5 minutes)
- DNS propagation depends on client TTL respect (60s configured)
- Cross-region data transfer costs can be significant under heavy load
- Failback to primary requires manual intervention

## Future Enhancements

- [ ] Automate RDS replica promotion with Lambda
- [ ] Add CloudWatch dashboard for DR status
- [ ] Implement automated failover testing (chaos engineering)
- [ ] Add DynamoDB global tables for session state
- [ ] Integrate with AWS Backup for centralized backup management
- [ ] Add multi-region WAF rules

## Compliance

This architecture supports:

- **POPIA** (South Africa): Data residency in af-south-1
- **GDPR**: EU data processing in eu-west-1
- **ISO 27001**: Disaster recovery and business continuity requirements
- **SOC 2**: Availability and security controls

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit changes (`git commit -am 'Add feature'`)
4. Push to branch (`git push origin feature/improvement`)
5. Open a Pull Request



## Acknowledgments

- AWS Well-Architected Framework for DR best practices
- HashiCorp Terraform documentation
- AWS Solutions Library disaster recovery patterns

## Support

For issues or questions:
- Open an issue on GitHub
- Review [CHANGELOG.md](CHANGELOG.md) for recent updates
- Check [SECURITY.md](SECURITY.md) for security-related questions

---

**Built with**: Terraform, AWS Multi-Region Architecture, Infrastructure as Code Best Practices
