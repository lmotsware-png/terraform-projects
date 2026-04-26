# =============================================================
# IAM.TF
# =============================================================
# IAM = Identity and Access Management
# This file creates all the ROLES and PERMISSIONS
#
# Remember our IAM discussion:
# IAM Role = a staff ID card that gives permissions
# IAM Policy = the list of what that ID card can access
#
# In this architecture we need THREE roles:
# 1. Transfer Family Role — permission to write files to S3
# 2. Lambda Role — permission to read from S3 and write to database
# 3. Transfer Family User Role — permission for the SFTP user
# =============================================================

# =============================================================
# ROLE 1 — AWS Transfer Family Role
# =============================================================
# This role gives Transfer Family permission to:
# - Write uploaded SFTP files into S3
# - Read files from S3 if needed
#
# Without this role — Transfer Family cannot touch S3
# It would receive the file but have nowhere to put it

resource "aws_iam_role" "transfer_family" {
  name = "${var.project_name}-transfer-family-role"
  # name = what this role is called in AWS

  assume_role_policy = jsonencode({
    # assume_role_policy = WHO is allowed to USE this role
    # jsonencode() converts Terraform map format to JSON format
    # AWS requires this policy in JSON
    Version = "2012-10-17"
    # Version = the IAM policy language version — always this date

    Statement = [{
      Action = "sts:AssumeRole"
      # Action = what action is being allowed
      # sts:AssumeRole = allows a service to become this role
      # STS = Security Token Service — handles role assumption

      Effect = "Allow"
      # Effect = "Allow" means YES this is permitted
      # Effect = "Deny" would block it

      Principal = {
        Service = "transfer.amazonaws.com"
        # Principal = WHO gets to use this role
        # transfer.amazonaws.com = the AWS Transfer Family service
        # This says: "AWS Transfer Family service can use this role"
        # Not a human — not an EC2 — specifically Transfer Family
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-transfer-family-role"
    Purpose = "Allows Transfer Family to read and write S3"
  })
}

# Policy — what Transfer Family can actually DO with S3
resource "aws_iam_role_policy" "transfer_family_s3" {
  name = "${var.project_name}-transfer-family-s3-policy"
  role = aws_iam_role.transfer_family.id
  # role = attach this policy to the Transfer Family role above
  # aws_iam_role.transfer_family.id = get the ID of that role

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketAccess"
        # Sid = Statement ID = just a label for this statement
        # Helps you identify which rule did what in audit logs

        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          # ListBucket = see what files are in the bucket
          # SFTP clients need this to do "ls" (list files) command
          "s3:GetBucketLocation"
          # GetBucketLocation = find which region the bucket is in
        ]
        Resource = aws_s3_bucket.orders.arn
        # Resource = which S3 bucket these actions apply to
        # We only give access to OUR specific bucket
        # Not all buckets in the account
      },
      {
        Sid    = "AllowS3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          # PutObject = UPLOAD a file to S3
          # This is the main action — Transfer Family uploads received files

          "s3:GetObject",
          # GetObject = DOWNLOAD a file from S3
          # SFTP clients can also download files if needed

          "s3:DeleteObject",
          # DeleteObject = delete a file
          # Some SFTP operations need delete permission

          "s3:GetObjectVersion"
          # GetObjectVersion = get a specific version of a file
          # Needed because we enabled versioning on the bucket
        ]
        Resource = "${aws_s3_bucket.orders.arn}/*"
        # ${aws_s3_bucket.orders.arn}/* means:
        # The bucket ARN + /* = ALL objects inside the bucket
        # The bucket itself vs objects inside are different resources in IAM
      }
    ]
  })
}

# =============================================================
# ROLE 2 — Lambda Execution Role
# =============================================================
# This role gives Lambda permission to:
# - Read order files from S3
# - Write logs to CloudWatch (so we can see what happened)
# - Connect to RDS database
# - Run inside our VPC

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
        # lambda.amazonaws.com = the Lambda service gets this role
        # Different from transfer.amazonaws.com above
        # Each AWS service has its own service identifier
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-lambda-role"
    Purpose = "Allows Lambda to read S3 files and write to database"
  })
}

# Attach AWS managed policy for Lambda VPC access
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  # policy_arn = the ARN of the policy to attach
  # This is an AWS MANAGED policy — AWS wrote it for you
  # AWSLambdaVPCAccessExecutionRole gives Lambda:
  # - Permission to create network interfaces in VPC
  # - Permission to write logs to CloudWatch
  # Lambda needs to create ENIs to run inside a VPC
}

# Custom policy for Lambda to access S3 and other services
resource "aws_iam_role_policy" "lambda_s3" {
  name = "${var.project_name}-lambda-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          # Lambda reads the order file that was just uploaded
          "s3:GetObjectVersion",
          # Get specific version if needed
          "s3:ListBucket"
          # List files in bucket
        ]
        Resource = [
          aws_s3_bucket.orders.arn,
          "${aws_s3_bucket.orders.arn}/*"
          # Both the bucket and all objects inside
        ]
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          # Create a log group to store Lambda logs
          "logs:CreateLogStream",
          # Create a log stream inside the log group
          "logs:PutLogEvents"
          # Write log messages
          # Without this — Lambda cannot write any logs
          # You would be flying blind — no visibility into what happened
        ]
        Resource = "arn:aws:logs:*:*:*"
        # Allow logging to any CloudWatch log group
        # * = wildcard = any region, any account, any log group
      },
      {
        Sid    = "AllowSSMParameterStore"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          # Read a single parameter from Parameter Store
          "ssm:GetParameters",
          # Read multiple parameters at once
          "ssm:GetParametersByPath"
          # Read all parameters under a path
          # Example: /woolworths-orders/production/db-password
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
        # Only allow access to OUR parameters
        # Not all parameters in the account
        # ${var.project_name}/* = woolworths-orders/*
      }
    ]
  })
}

# =============================================================
# ROLE 3 — Transfer Family SFTP User Role
# =============================================================
# This is specific to the SFTP USER (the ERP system login)
# It controls which S3 folders the SFTP user can access
# Like a home directory for the SFTP user

resource "aws_iam_role" "sftp_user" {
  name = "${var.project_name}-sftp-user-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "transfer.amazonaws.com"
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-sftp-user-role"
    Purpose = "Scopes SFTP user access to specific S3 folder"
  })
}

# Policy — limits the SFTP user to ONLY their upload folder
resource "aws_iam_role_policy" "sftp_user" {
  name = "${var.project_name}-sftp-user-policy"
  role = aws_iam_role.sftp_user.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowListingOfUserFolder"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.orders.arn]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "uploads/",
              "uploads/*"
              # This condition means:
              # User can only LIST files in the uploads/ folder
              # Not the root of the bucket
              # Not any other folder
            ]
          }
        }
      },
      {
        Sid    = "AllowUserToReadWriteInHomeFolder"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          # Upload files — the ERP system needs this
          "s3:GetObject",
          # Download files
          "s3:DeleteObjectVersion",
          "s3:DeleteObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.orders.arn}/uploads/*"
        # ONLY allow access to the uploads/ folder
        # The SFTP user CANNOT access any other folder
        # Cannot access the root — only their designated folder
        # This is called "home directory" restriction
      }
    ]
  })
}

# =============================================================
# CLOUDWATCH LOG GROUP
# =============================================================
# CloudWatch = AWS monitoring and logging service
# All Lambda logs go here
# All Transfer Family logs go here
# Like a central logging server for everything

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-order-processor"
  # name = the path in CloudWatch where logs appear
  # Convention: /aws/lambda/FUNCTION_NAME
  # This is the standard naming pattern

  retention_in_days = 30
  # retention_in_days = how long to keep logs
  # 30 days = delete logs after 30 days automatically
  # Saves cost — old logs not kept forever
  # Adjust based on compliance requirements

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-lambda-logs"
  })
}

resource "aws_cloudwatch_log_group" "transfer_family" {
  name              = "/aws/transfer/${var.project_name}"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-transfer-family-logs"
  })
}
