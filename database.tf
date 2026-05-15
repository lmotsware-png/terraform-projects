# =============================================================
# DATABASE.TF
# =============================================================
# This file handles ALL database resources
# Main RDS in Cape Town — primary database
# RDS Read Replica in Ireland — always receiving updates
# S3 bucket with Cross Region Replication
#
# Remember our discussion:
# RDS = your live transactional database (account balances, orders)
# S3 = your file storage (PDFs, images, videos)
# Both need to be replicated to DR region
# =============================================================

# =============================================================
# DATABASE SUBNET GROUP — Main Region
# =============================================================
# RDS needs to know which subnets it can use
# We put it in PRIVATE subnets — not accessible from internet
# Only your EC2 instances can reach the database

resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-main-db-subnet-group"
  subnet_ids = [
    aws_subnet.main_private_1.id,
    aws_subnet.main_private_2.id
    # Two private subnets across two AZs
    # This enables Multi AZ for the database
  ]

  tags = {
    Name = "${var.app_name}-main-db-subnet-group"
  }
}

# =============================================================
# RDS SECURITY GROUP — Main Region
# =============================================================
# Database only accepts connections from EC2 instances
# Not from internet — never expose database publicly

resource "aws_security_group" "main_rds" {
  name        = "${var.app_name}-main-rds-sg"
  description = "Security group for main RDS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306      # MySQL/Aurora port
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.main_ec2.id]
    # ONLY allow connections from EC2 instances
    # Database is invisible to the internet
    description     = "Allow MySQL only from EC2 instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-main-rds-sg"
  }
}

# =============================================================
# RDS PRIMARY DATABASE — Main Region (Cape Town)
# =============================================================
# This is your main live database
# All reads and writes happen here during normal operation
# multi_az = true means AWS automatically creates a standby
# in another AZ within Cape Town region — high availability

resource "aws_db_instance" "main" {
  identifier        = "${var.app_name}-main-db"
  # identifier is the name of your RDS instance in AWS console

  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.main_db_instance_class   # db.m5.large — production size

  db_name           = var.db_name
  username          = var.db_username
  password          = var.db_password

  # Storage settings
  allocated_storage     = 100        # 100 GB storage
  max_allocated_storage = 500        # Auto scales up to 500 GB if needed
  storage_type          = "gp3"      # General purpose SSD — remember our storage discussion
  storage_encrypted     = true       # Always encrypt database storage

  # Multi AZ — creates automatic standby in another AZ
  # If primary fails — standby takes over automatically
  # This is HIGH AVAILABILITY within Cape Town region
  multi_az = true

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.main_rds.id]
  publicly_accessible    = false   # NEVER make database public

  # Backups
  backup_retention_period = 7      # Keep backups for 7 days
  backup_window           = "03:00-04:00"   # Backup at 3am
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # This is CRITICAL for disaster recovery
  # Allows creating a Read Replica in another region
  # Without this — cross region replication is not possible
  backup_retention_period         = 7
  copy_tags_to_snapshot           = true

  skip_final_snapshot = false
  final_snapshot_identifier = "${var.app_name}-main-db-final-snapshot"
  # When you delete this database — take a final backup snapshot

  tags = {
    Name        = "${var.app_name}-main-db"
    Environment = var.environment
  }
}

# =============================================================
# RDS READ REPLICA — DR Region (Ireland)
# =============================================================
# This is your warm standby database
# It continuously receives all changes from the main database
# If main database goes down — you PROMOTE this replica
# Promoted replica becomes the new primary
# Starts accepting writes — business continues

resource "aws_db_instance" "dr_replica" {
  provider = aws.dr    # Build this in Ireland

  identifier     = "${var.app_name}-dr-replica"
  instance_class = var.dr_db_instance_class   # db.t3.medium — smaller than main

  # This line makes it a replica of the main database
  # replicate_source_db points to the main database ARN
  # ARN = Amazon Resource Name — unique identifier for every AWS resource
  replicate_source_db = aws_db_instance.main.arn

  # Networking in DR region
  vpc_security_group_ids = [aws_security_group.dr_rds.id]
  db_subnet_group_name   = aws_db_subnet_group.dr.name

  # Storage — same encryption requirement
  storage_encrypted = true
  storage_type      = "gp3"

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name        = "${var.app_name}-dr-replica"
    Environment = var.environment
    Purpose     = "warm-standby-replica"
    Note        = "Promote to primary during disaster recovery"
  }
}

# Database subnet group for DR region
resource "aws_db_subnet_group" "dr" {
  provider   = aws.dr
  name       = "${var.app_name}-dr-db-subnet-group"
  subnet_ids = [
    aws_subnet.dr_private_1.id,
    aws_subnet.dr_private_2.id
  ]

  tags = {
    Name = "${var.app_name}-dr-db-subnet-group"
  }
}

# Security group for DR database
resource "aws_security_group" "dr_rds" {
  provider    = aws.dr
  name        = "${var.app_name}-dr-rds-sg"
  description = "Security group for DR RDS replica"
  vpc_id      = aws_vpc.dr.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.dr_ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-dr-rds-sg"
  }
}

# =============================================================
# S3 BUCKETS WITH CROSS REGION REPLICATION
# =============================================================
# Remember our discussion — S3 stores files, PDFs, images, videos
# We need these files available in DR region too
# Cross Region Replication automatically copies every file
# from Cape Town bucket to Ireland bucket

# IAM Role for S3 Replication
# S3 needs permission to copy files to another region
# This is the staff ID card for S3 replication
resource "aws_iam_role" "s3_replication" {
  name = "${var.app_name}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      # S3 service is allowed to use this role
    }]
  })
}

# Policy giving S3 permission to replicate
resource "aws_iam_role_policy" "s3_replication" {
  name = "${var.app_name}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Permission to read from source bucket
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = aws_s3_bucket.main.arn
      },
      {
        # Permission to read objects from source
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.main.arn}/*"
        # /* means all objects inside the bucket
      },
      {
        # Permission to write objects to destination
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.dr.arn}/*"
      }
    ]
  })
}

# MAIN S3 BUCKET — Cape Town
resource "aws_s3_bucket" "main" {
  bucket = "${var.app_name}-main-files-${data.aws_caller_identity.current.account_id}"
  # Account ID makes bucket name globally unique
  # Remember — S3 bucket names must be unique across entire AWS globally

  tags = {
    Name        = "${var.app_name}-main-files"
    Environment = var.environment
  }
}

# Enable versioning on main bucket
# Versioning is REQUIRED for Cross Region Replication to work
# It also means you can recover accidentally deleted files
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access to main bucket
# Files are NOT accessible from internet directly
# They are accessed via your application only
resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt main bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CROSS REGION REPLICATION CONFIGURATION
# This is the magic that automatically copies files to Ireland
resource "aws_s3_bucket_replication_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "replicate-everything"
    status = "Enabled"   # Turn on replication

    filter {}
    # Empty filter means replicate ALL objects
    # You could filter to replicate only specific folders

    destination {
      bucket        = aws_s3_bucket.dr.arn   # Send to Ireland bucket
      storage_class = "STANDARD"
    }

    delete_marker_replication {
      status = "Enabled"
      # If file deleted in Cape Town — also delete in Ireland
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.main,
    aws_s3_bucket_versioning.dr
    # Versioning must be enabled on both buckets first
  ]
}

# DR S3 BUCKET — Ireland
resource "aws_s3_bucket" "dr" {
  provider = aws.dr   # Build this in Ireland
  bucket   = "${var.app_name}-dr-files-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.app_name}-dr-files"
    Environment = var.environment
    Purpose     = "disaster-recovery-replica"
  }
}

# Enable versioning on DR bucket — required for replication
resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "dr" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Data source to get current AWS account ID
# Used for making S3 bucket names unique
data "aws_caller_identity" "current" {}
