# AWS Warm Standby Disaster Recovery Infrastructure

## Project Overview
This project demonstrates a production-grade AWS Warm Standby 
Disaster Recovery architecture built entirely with Terraform (IaC).

The infrastructure replicates a real-world scenario where a 
financial/media company (SABC News) requires high availability 
and disaster recovery across two AWS regions.

## Architecture Diagram
Main Region (Cape Town - af-south-1) → DR Region (Ireland - eu-west-1)

## What This Infrastructure Builds

### Main Region (Cape Town)
- VPC with public and private subnets across 2 Availability Zones
- Application Load Balancer with health checks
- Auto Scaling Group (min 2, max 10 EC2 instances)
- RDS MySQL with Multi-AZ enabled
- S3 bucket with versioning and encryption

### DR Region (Ireland) — Warm Standby
- Identical architecture but scaled down
- Auto Scaling Group (min 1, max 10 EC2 instances)
- RDS Read Replica continuously synced from main region
- S3 bucket with Cross Region Replication
- Route 53 health checks with automatic DNS failover

## Disaster Recovery Flow
1. Route 53 monitors main region every 30 seconds
2. If main region fails — DNS automatically switches to DR region
3. Auto Scaling Group scales up in DR region
4. RDS Read Replica promoted to primary
5. S3 files already replicated — no data loss
6. Recovery Time Objective (RTO): Minutes

## Technologies Used
- AWS (EC2, RDS, S3, Route 53, ALB, Auto Scaling, VPC)
- Terraform (Infrastructure as Code)
- GitHub (Version Control)

## AWS Services Covered
- EC2 with Auto Scaling Groups
- Application Load Balancer
- RDS MySQL with Multi-AZ and Cross Region Replication
- S3 with Cross Region Replication
- Route 53 with Failover Routing
- VPC, Subnets, Security Groups, Internet Gateway
- IAM Roles and Policies

## Author
**Imotsware**
- AWS Solutions Architect Associate (In Progress)
- CCNA Certified
- N6 Electrical Engineering
- Former Network Technician — SANDF Tempe Military Base
- Former Broadcast Technician — Sentech (SABC Transmission)