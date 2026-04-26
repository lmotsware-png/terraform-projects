# =============================================================
# S3.TF
# =============================================================
# This file creates the S3 bucket where uploaded order files land
#
# Remember our S3 discussion:
# S3 = Simple Storage Service = your file storage in the cloud
# Like an external hard drive accessible over the network
#
# In this architecture:
# 1. Legacy ERP sends file via SFTP
# 2. Transfer Family receives the file
# 3. Transfer Family automatically puts it in THIS S3 bucket
# 4. Lambda reads from THIS bucket to process the order
# =============================================================

# =============================================================
# S3 BUCKET — Main orders bucket
# =============================================================

resource "aws_s3_bucket" "orders" {
  bucket = "${var.s3_bucket_name}-${data.aws_caller_identity.current.account_id}"
  # bucket = the name of the S3 bucket
  #
  # WHY add account_id to the name?
  # S3 bucket names must be GLOBALLY UNIQUE across ALL of AWS worldwide
  # There are millions of S3 buckets — "woolworths-orders" might already exist
  # By adding YOUR account ID — the name becomes unique to you
  # Example: woolworths-orders-files-123456789012
  #
  # data.aws_caller_identity.current.account_id
  # = read from the data source we defined in networking.tf
  # = your AWS account ID number

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-orders-bucket"
    Purpose = "Stores order files received via SFTP from legacy ERP"
  })
}

# =============================================================
# BLOCK ALL PUBLIC ACCESS
# =============================================================
# This is CRITICAL security
# By default AWS might allow public access to S3 buckets
# We want ZERO public access — this bucket is internal only
# Order files contain sensitive business data — never expose publicly

resource "aws_s3_bucket_public_access_block" "orders" {
  bucket = aws_s3_bucket.orders.id
  # bucket = which bucket to apply these rules to
  # aws_s3_bucket.orders.id = the ID of the bucket we created above

  block_public_acls       = true
  # ACL = Access Control List
  # block_public_acls = true means nobody can make files public via ACL
  # Even if someone tries to set a file as public — it gets blocked

  block_public_policy     = true
  # Prevents bucket policies that allow public access
  # Even if someone writes a policy trying to make bucket public — blocked

  ignore_public_acls      = true
  # Ignores any existing public ACLs — treats them as if they do not exist

  restrict_public_buckets = true
  # Even if somehow public access was granted — this overrides it
  # Maximum protection — four layers of public access blocking
}

# =============================================================
# BUCKET VERSIONING
# =============================================================
# Versioning keeps every version of every file
# If an order file gets overwritten or corrupted — you can recover
# Think of it like track changes in Microsoft Word
# Every time a file changes — old version is kept

resource "aws_s3_bucket_versioning" "orders" {
  bucket = aws_s3_bucket.orders.id

  versioning_configuration {
    status = "Enabled"
    # Enabled = keep all versions of all files
    # If ERP sends same filename twice — both versions kept
    # You can always go back to any previous version
  }
}

# =============================================================
# BUCKET ENCRYPTION
# =============================================================
# Encrypt all files stored in the bucket
# Order data is sensitive business information
# Even if someone somehow accessed the storage — data is unreadable
# Without the encryption key

resource "aws_s3_bucket_server_side_encryption_configuration" "orders" {
  bucket = aws_s3_bucket.orders.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      # AES256 = Advanced Encryption Standard with 256-bit key
      # This is military grade encryption
      # AWS manages the keys automatically — you do not need to worry
      # Every file stored is automatically encrypted
      # Every file retrieved is automatically decrypted
    }
    bucket_key_enabled = true
    # bucket_key_enabled = true reduces encryption costs
    # AWS creates one key per bucket instead of one per file
    # Saves up to 99% on AWS KMS encryption costs
  }
}

# =============================================================
# BUCKET LIFECYCLE RULES
# =============================================================
# Lifecycle rules automatically manage files over time
# Order files do not need to stay as expensive standard storage forever
# After processing — they can move to cheaper storage
# This saves money automatically

resource "aws_s3_bucket_lifecycle_configuration" "orders" {
  bucket = aws_s3_bucket.orders.id

  rule {
    id     = "order-files-lifecycle"
    status = "Enabled"

    # This filter applies to ALL files in the bucket
    filter {
      prefix = ""
      # prefix = "" means apply to all files
      # You could use prefix = "orders/" to apply to only one folder
    }

    # TRANSITION 1 — After 30 days move to Standard-IA
    transition {
      days          = 30
      # days = how many days after upload
      storage_class = "STANDARD_IA"
      # STANDARD_IA = Standard Infrequent Access
      # Cheaper than standard but costs more to retrieve
      # Perfect for processed orders — rarely accessed but keep for audits
      # About 46% cheaper than standard storage
    }

    # TRANSITION 2 — After 90 days move to Glacier
    transition {
      days          = 90
      storage_class = "GLACIER"
      # GLACIER = archive storage — very cheap
      # Takes 1-12 hours to retrieve files
      # Perfect for compliance archiving — keep records but rarely need them
      # About 68% cheaper than standard storage
    }

    # DELETE — After 365 days delete the file completely
    expiration {
      days = 365
      # After 1 year — order files are deleted automatically
      # Adjust this based on your compliance requirements
      # Some industries need 7 years — just change the number
    }

    # Also clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
      # If a file upload started but never finished
      # Clean it up after 7 days — saves storage costs
    }
  }
}

# =============================================================
# BUCKET NOTIFICATION — Tell Lambda when a file arrives
# =============================================================
# This is the KEY to immediate processing — no polling
# When a file lands in S3 — this immediately notifies Lambda
# Lambda does not check every few minutes — it gets told instantly
#
# Think of it like a doorbell vs looking out the window
# Without notification = look out window every 5 minutes (polling)
# With notification = doorbell rings the moment someone arrives

resource "aws_s3_bucket_notification" "orders" {
  bucket = aws_s3_bucket.orders.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.order_processor.arn
    # lambda_function_arn = which Lambda to notify
    # ARN = Amazon Resource Name = unique ID for every AWS resource
    # We reference the Lambda we will create in lambda.tf

    events = ["s3:ObjectCreated:*"]
    # events = which events trigger the notification
    # s3:ObjectCreated:* means ANY type of object creation
    # * means wildcard — covers Put, Post, Copy, CompleteMultipartUpload
    # Basically — any time a NEW file appears — trigger Lambda

    filter_prefix = "uploads/"
    # filter_prefix = only trigger for files in the "uploads/" folder
    # This means Lambda only runs for new order files
    # Not for any other files that might be in the bucket
    # The SFTP server will upload files to the uploads/ folder

    filter_suffix = ".csv"
    # filter_suffix = only trigger for .csv files
    # The legacy ERP sends CSV (comma separated values) files
    # If someone accidentally puts a .txt or .pdf — Lambda ignores it
    # Only trigger for the exact file type we expect
  }

  depends_on = [aws_lambda_permission.s3_invoke]
  # depends_on = build this ONLY AFTER the Lambda permission exists
  # S3 needs permission to invoke Lambda before we set up notifications
  # If we set up notification before permission — it would fail
  # Terraform handles this ordering for us
}
