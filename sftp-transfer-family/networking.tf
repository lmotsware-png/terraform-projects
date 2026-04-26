# =============================================================
# NETWORKING.TF
# =============================================================
# This file builds ALL the networking infrastructure
# VPC, Subnets, Security Groups
#
# Remember our discussion about networking:
# VPC = your private fence around your AWS resources
# Subnets = sections inside that fence
# Security Groups = the rules about who can enter each section
#
# This SFTP server is INTERNAL — never exposed to internet
# That is why we use PRIVATE subnets only
# No internet gateway needed — traffic comes via VPN/Direct Connect
# =============================================================

# =============================================================
# DATA SOURCES
# =============================================================
# Data sources are how Terraform READS existing information from AWS
# Instead of creating something new — we ask AWS for information
#
# The keyword "data" means READ — not create
# The keyword "resource" means CREATE

# Get all available Availability Zones in our region
data "aws_availability_zones" "available" {
  state = "available"
  # state = "available" means only give us AZs that are working
  # In Cape Town region this gives us: af-south-1a, af-south-1b, af-south-1c
  # We use this to deploy our subnets across multiple AZs
}

# Get current AWS account ID
# Used to make S3 bucket names globally unique
data "aws_caller_identity" "current" {}
# {} means no filters — just get my account information
# We use this as: data.aws_caller_identity.current.account_id

# =============================================================
# VPC — Virtual Private Cloud
# =============================================================
# This is the main network container
# Everything lives inside this VPC
# Think of it as the fence around your property

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  # cidr_block = the IP address range for the whole VPC
  # We get this value from variables.tf
  # Default is 10.0.0.0/16 = 65,536 IP addresses

  enable_dns_hostnames = true
  # Allows resources inside VPC to have DNS names
  # Example: ip-10-0-1-5.af-south-1.compute.internal
  # The Transfer Family server needs this to register itself

  enable_dns_support = true
  # Enables the DNS resolver inside the VPC
  # Without this — resources cannot resolve domain names
  # The SSM Agent and Lambda need DNS to call AWS services

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
    # merge() combines two sets of tags together
    # var.common_tags = all the standard tags from variables.tf
    # The second {} adds the Name tag specific to this resource
    # Result: all common tags PLUS Name = "woolworths-orders-vpc"
  })
}

# =============================================================
# PRIVATE SUBNETS
# =============================================================
# We create TWO private subnets — one in each AZ
# This gives us HIGH AVAILABILITY
# If Cape Town AZ A loses power — AZ B keeps receiving SFTP files
#
# These are PRIVATE subnets — no direct internet access
# Traffic only comes via VPN or Direct Connect from on-premises

resource "aws_subnet" "private_az1" {
  vpc_id = aws_vpc.main.id
  # vpc_id = which VPC does this subnet belong to
  # aws_vpc.main.id = get the ID of the VPC we just created above
  # This is how Terraform connects resources to each other

  cidr_block = var.private_subnet_cidr_az1
  # IP range for this subnet
  # Default: 10.0.1.0/24 = 256 IP addresses

  availability_zone = data.aws_availability_zones.available.names[0]
  # data.aws_availability_zones.available = the list we got above
  # .names[0] = first AZ in the list = af-south-1a
  # [0] means first item — programming counts from 0

  map_public_ip_on_launch = false
  # false = do NOT give public IP addresses to resources in this subnet
  # This is a PRIVATE subnet — no public IPs
  # Resources are not directly reachable from internet

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-subnet-az1"
    Type = "Private"
    AZ   = "AZ1"
  })
}

resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_az2
  # Default: 10.0.2.0/24 = different range from AZ1

  availability_zone = data.aws_availability_zones.available.names[1]
  # .names[1] = second AZ in the list = af-south-1b
  # [1] means second item

  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-subnet-az2"
    Type = "Private"
    AZ   = "AZ2"
  })
}

# =============================================================
# VPC ENDPOINTS
# =============================================================
# This is very important and often missed by beginners
#
# Our Lambda function runs inside the VPC
# Lambda needs to talk to S3 to read the uploaded files
# But S3 is OUTSIDE the VPC — it is an AWS managed service
#
# Without VPC Endpoint:
# Lambda → must go to internet → come back to S3
# This means we need internet access = security risk
#
# With VPC Endpoint:
# Lambda → private AWS network → S3
# Traffic never touches the internet
# Much more secure
#
# Think of it like a private corridor between your office
# and the post room — you do not go outside

# S3 VPC Endpoint — allows Lambda inside VPC to reach S3 privately
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  # service_name = which AWS service to connect to
  # Format is always: com.amazonaws.REGION.SERVICE
  # Example: com.amazonaws.af-south-1.s3

  vpc_endpoint_type = "Gateway"
  # Gateway type is used for S3 and DynamoDB
  # It is free — no additional cost
  # Interface type is used for other services and costs money

  route_table_ids = [aws_route_table.private.id]
  # Which route tables should use this endpoint
  # When Lambda sends traffic to S3 — it uses this private path

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-s3-endpoint"
  })
}

# SSM VPC Endpoint — allows Systems Manager to work inside VPC
# Lambda needs to be managed — SSM handles that
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  # Interface type creates an ENI (network card) in your subnet
  # Traffic goes through that ENI privately

  subnet_ids          = [
    aws_subnet.private_az1.id,
    aws_subnet.private_az2.id
  ]
  # Deploy the endpoint in both subnets for high availability

  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  # private_dns_enabled = true means when Lambda calls ssm.amazonaws.com
  # DNS resolves to the private endpoint — not the internet address

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ssm-endpoint"
  })
}

# =============================================================
# ROUTE TABLE
# =============================================================
# Route tables tell traffic where to go
# From your CCNA — this is like a routing table on a router
# Our private route table has no internet route
# Only route is to S3 via VPC endpoint

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-rt"
    Type = "Private — no internet route"
  })
}

# Associate private route table with both private subnets
resource "aws_route_table_association" "private_az1" {
  subnet_id      = aws_subnet.private_az1.id
  route_table_id = aws_route_table.private.id
  # This connects the route table to subnet AZ1
  # All traffic from AZ1 subnet follows these routing rules
}

resource "aws_route_table_association" "private_az2" {
  subnet_id      = aws_subnet.private_az2.id
  route_table_id = aws_route_table.private.id
}

# =============================================================
# SECURITY GROUPS
# =============================================================
# Security groups are virtual firewalls
# From your networking background — like ACLs on a switch
# They control what traffic is allowed IN (ingress) and OUT (egress)

# SECURITY GROUP 1 — For the SFTP Transfer Family Server
resource "aws_security_group" "sftp_server" {
  name        = "${var.project_name}-sftp-sg"
  description = "Security group for internal SFTP Transfer Family server — only allows on-premises connections"
  vpc_id      = aws_vpc.main.id

  # INBOUND RULE — only allow SFTP from on-premises network
  ingress {
    description = "SFTP from on-premises ERP system only"
    from_port   = 22
    # SFTP uses port 22 — same as SSH
    # From your networking — port 22 is the standard SFTP/SSH port
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
    # cidr_blocks = which IP addresses are allowed
    # var.on_premises_cidr = only the company office network
    # Default: 192.168.1.0/24
    # This means ONLY the office network can connect via SFTP
    # Someone on the internet trying port 22 gets BLOCKED
  }

  # OUTBOUND RULE — allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    # -1 means ALL protocols
    cidr_blocks = ["0.0.0.0/0"]
    # Allow outbound to anywhere
    # The SFTP server needs to write files to S3
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-sftp-sg"
    Purpose = "Restrict SFTP access to on-premises only"
  })
}

# SECURITY GROUP 2 — For Lambda function
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda order processor function"
  vpc_id      = aws_vpc.main.id

  # Lambda does not accept inbound connections
  # It is triggered by events — not by network connections
  # So no ingress rules needed

  # OUTBOUND — Lambda needs to reach S3 and RDS
  egress {
    description = "Allow Lambda to reach AWS services and databases"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # Lambda needs to:
    # - Read files from S3 (via VPC endpoint)
    # - Write to RDS database
    # - Call other AWS services
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-lambda-sg"
    Purpose = "Lambda order processor networking"
  })
}

# SECURITY GROUP 3 — For VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  # Allow HTTPS from within VPC
  ingress {
    description = "HTTPS from VPC resources to AWS services"
    from_port   = 443
    # AWS services communicate over HTTPS port 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    # Only allow from within our own VPC
    # 10.0.0.0/16 = our VPC IP range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-endpoints-sg"
  })
}
