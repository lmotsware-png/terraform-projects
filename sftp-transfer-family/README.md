# AWS Transfer Family SFTP to S3 Order Processing Infrastructure

## Project Overview
This project solves a real-world enterprise problem:
A legacy ERP system that **cannot be modified** needs to send order files to AWS for processing.

Built entirely with **Terraform (Infrastructure as Code)**.

---

## The Business Problem

```
Legacy ERP System (on-premises)
├── Cannot be modified — ever
├── Only speaks SFTP protocol  
├── Sends customer order CSV files
└── Needs files processed IMMEDIATELY
```

---

## Architecture Diagram

```
ON-PREMISES                          AWS VPC (INTERNAL)
───────────                          ──────────────────

Legacy ERP System
(SFTP Client)
      │
      │ SFTP over VPN/Direct Connect
      │ Port 22
      ▼
Transfer Family SFTP Server ──────→ S3 Bucket (orders)
(Internal VPC endpoint)                    │
(Multi-AZ: AZ1 + AZ2)                     │ Immediate trigger
(NOT on internet)                          ▼
                                     Lambda Function
                                     (order_processor)
                                           │
                                           ▼
                                     Downstream Services
                                     (RDS, DynamoDB, Analytics)
```

---

## How It Works — Step by Step

1. **Woolworths store** places an order in the legacy ERP system
2. **ERP system** generates an order CSV file
3. **ERP connects** to Transfer Family SFTP server via VPN tunnel
4. **ERP uploads** the CSV file to `/orders/` folder
5. **Transfer Family** receives the file and stores it in **S3**
6. **S3 notification** immediately triggers **Lambda** — no polling
7. **Lambda** reads the file, validates and processes each order line
8. **Orders saved** to downstream systems (RDS/DynamoDB)
9. **Warehouse** picks and dispatches the order

**Total time from upload to processing: seconds**

---

## Why Each Technology Was Chosen

| Requirement | Solution | Why |
|---|---|---|
| Must speak SFTP | AWS Transfer Family | Fully managed SFTP server — legacy system unchanged |
| Process IMMEDIATELY | S3 notification + Lambda | Triggered instantly on upload — no polling |
| Highly Available | Transfer Family in 2 AZs | ENI in AZ1 and AZ2 — survives AZ failure |
| Not on internet | endpoint_type = VPC | Internal endpoint — accessible only via VPN |
| Secure | Security group + IAM | Only on-premises CIDR allowed on port 22 |
| Scalable | Lambda + S3 | Both auto-scale automatically |

---

## Files in This Project

| File | Purpose |
|---|---|
| `providers.tf` | AWS provider and region configuration |
| `variables.tf` | All configurable settings in one place |
| `networking.tf` | VPC, subnets, security groups, VPC endpoints |
| `s3.tf` | S3 bucket with encryption, versioning, lifecycle rules |
| `iam.tf` | IAM roles and policies for all services |
| `transfer_family.tf` | SFTP server, user, workflow configuration |
| `lambda.tf` | Lambda function with Python order processing code |
| `outputs.tf` | Values displayed after deployment |

---

## AWS Services Used

- **AWS Transfer Family** — Managed SFTP server
- **Amazon S3** — Order file storage with encryption and versioning
- **AWS Lambda** — Serverless order processing (Python 3.11)
- **Amazon VPC** — Private network with subnets across 2 AZs
- **IAM** — Roles and policies for least privilege access
- **CloudWatch** — Logging and monitoring
- **VPC Endpoints** — Private connectivity to AWS services
- **AWS Systems Manager Parameter Store** — Secure configuration storage

---

## Security Features

- ✅ SFTP server NOT exposed to internet (VPC internal endpoint)
- ✅ Security group restricts access to on-premises CIDR only
- ✅ S3 bucket has all public access blocked
- ✅ All S3 data encrypted at rest (AES-256)
- ✅ IAM least privilege — each service only has permissions it needs
- ✅ SFTP user restricted to uploads/ folder only
- ✅ Lambda runs inside private VPC subnet
- ✅ VPC endpoints — traffic never touches internet
- ✅ CloudWatch logging for full audit trail

---

## How to Deploy

### Prerequisites
- AWS CLI installed and configured
- Terraform >= 1.0 installed
- AWS account with appropriate permissions
- VPN or Direct Connect already established to on-premises

### Deploy

```bash
# 1. Clone this repository
git clone https://github.com/Imotsware-png/terraform-projects.git
cd terraform-projects/sftp-transfer-family

# 2. Initialize Terraform
terraform init

# 3. Preview what will be built
terraform plan -var="sftp_password=YourSecurePassword123"

# 4. Build the infrastructure
terraform apply -var="sftp_password=YourSecurePassword123"

# 5. Get the SFTP endpoint address from outputs
# Give this to your ERP/network team
```

### After Deployment
1. Get the SFTP endpoint from Terraform outputs
2. Configure your VPN/Direct Connect to reach the VPC
3. Configure the ERP system with:
   - **Host**: (from terraform output)
   - **Port**: 22
   - **Username**: erp-orders-user
   - **Password**: (what you set in sftp_password)
   - **Upload path**: /orders/

---

## Monitoring

**Lambda Logs:**
```
AWS Console → CloudWatch → Log Groups → /aws/lambda/woolworths-orders-order-processor
```

**SFTP Activity Logs:**
```
AWS Console → CloudWatch → Log Groups → /aws/transfer/woolworths-orders
```

---

## Author

**Lerato Motsware**
📧 lmotsware@gmail.com
🔗 LinkedIn: linkedin.com/in/lerato-motsware-83923017a
🔗 GitHub: github.com/Imotsware-png

### Qualifications
- CCNA — Cisco Certified Network Associate (Feb 2026)
- National Diploma: Electrical Engineering (Light Current) — Walter Sisulu University (Nov 2021)
- N3–N6 Electrical Engineering — Sedibeng College (2016)
- AWS Solutions Architect Associate (In Progress — Exam in may 2026)

### Experience
- Network Infrastructure Engineer — SANDF, Tempe Military Base (Feb 2024 – Jul 2025)
- Quality Assurance Engineer — Sentech SOC (Jun 2021 – Jan 2024)
- Technician Intern — Sentech SOC (Feb 2020 – Jan 2021)
