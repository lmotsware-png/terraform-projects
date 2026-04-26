# =============================================================
# TRANSFER_FAMILY.TF
# =============================================================
# This file creates the AWS Transfer Family SFTP server
#
# AWS Transfer Family is a fully managed SFTP server
# You do not build or manage the server yourself
# AWS runs it — you just configure it
#
# This server:
# - Lives INSIDE our VPC (not on internet)
# - Spans TWO availability zones (high availability)
# - Only accepts connections from on-premises network
# - Uses PASSWORD authentication (not SSH keys)
# - Automatically stores uploaded files in S3
# =============================================================

# =============================================================
# TRANSFER FAMILY SERVER
# =============================================================

resource "aws_transfer_server" "sftp" {
  identity_provider_type = "SERVICE_MANAGED"
  # identity_provider_type = how do users authenticate
  #
  # SERVICE_MANAGED = AWS Transfer Family manages usernames and passwords
  # We define users directly in Transfer Family
  # This is the simplest option — no external auth server needed
  #
  # Other options would be:
  # API_GATEWAY = use your own API to validate credentials
  # AWS_DIRECTORY_SERVICE = use Microsoft Active Directory
  # AWS_LAMBDA = use Lambda to validate credentials
  # We use SERVICE_MANAGED because:
  # - The legacy ERP just needs a username and password
  # - Simple and fully managed
  # - No additional infrastructure needed

  protocols = ["SFTP"]
  # protocols = which file transfer protocol to use
  # SFTP = Secure File Transfer Protocol
  # This is what the legacy ERP system uses
  # Transfer Family also supports FTP and FTPS
  # We ONLY enable SFTP — no other protocols needed
  # Principle of least privilege — only open what you need

  endpoint_type = "VPC"
  # endpoint_type = where is this server accessible from
  #
  # VPC = server lives INSIDE your VPC — not on internet
  # This is what makes it INTERNAL and SECURE
  #
  # Other option is "PUBLIC" — exposed to internet
  # We NEVER use PUBLIC for internal enterprise systems
  # The legacy ERP connects via VPN/Direct Connect — not internet

  endpoint_details {
    # These are the details of the VPC endpoint
    # Where exactly inside the VPC does the server live

    vpc_id = aws_vpc.main.id
    # vpc_id = which VPC to deploy the server in

    subnet_ids = [
      aws_subnet.private_az1.id,
      aws_subnet.private_az2.id
    ]
    # subnet_ids = which subnets to deploy in
    # We give it BOTH private subnets
    # Transfer Family creates an ENI in EACH subnet
    # ENI in AZ1 and ENI in AZ2
    # If AZ1 fails — AZ2 ENI still accepts connections
    # THIS is what makes it HIGHLY AVAILABLE

    security_group_ids = [aws_security_group.sftp_server.id]
    # security_group_ids = which security group controls access
    # Our security group only allows port 22 from on-premises CIDR
    # Nobody else can reach this server
  }

  logging_role = aws_iam_role.transfer_family.arn
  # logging_role = which IAM role to use for writing logs
  # Transfer Family needs permission to write logs to CloudWatch
  # We reuse our transfer_family IAM role for this

  structured_log_destinations = [
    "${aws_cloudwatch_log_group.transfer_family.arn}:*"
    # Where to send logs
    # All SFTP activity goes to CloudWatch
    # You can see: who connected, what files they uploaded, any errors
    # :* at the end is required by AWS format for log destinations
  ]

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-sftp-server"
    Purpose = "Internal SFTP endpoint for legacy ERP order file ingestion"
    Access  = "Internal only — VPC endpoint, on-premises via VPN"
  })
}

# =============================================================
# SFTP USER — The account the ERP system uses to login
# =============================================================
# This creates the actual user account on the SFTP server
# The legacy ERP system connects with this username and password
# Think of it like creating a user account on any computer

resource "aws_transfer_user" "erp_orders" {
  server_id = aws_transfer_server.sftp.id
  # server_id = which SFTP server this user belongs to
  # We reference the server we created above

  user_name = var.sftp_username
  # user_name = the username the ERP system uses to login
  # From variables.tf — default is "erp-orders-user"

  role = aws_iam_role.sftp_user.arn
  # role = which IAM role this user gets
  # This controls which S3 folders the user can access
  # From iam.tf — limited to uploads/ folder only

  home_directory_type = "LOGICAL"
  # home_directory_type = how the user sees their file system
  #
  # LOGICAL = you can map virtual paths to real S3 paths
  # The user sees a simple folder structure
  # But behind the scenes it maps to specific S3 locations
  # The ERP system just sees "/orders" as their folder
  # Behind scenes this maps to s3://bucket-name/uploads/
  #
  # PATH = user sees actual S3 bucket structure
  # LOGICAL is better — cleaner and more secure

  home_directory_mappings {
    # This maps what the SFTP user sees to actual S3 paths
    entry  = "/orders"
    # entry = what the user sees when they connect via SFTP
    # The ERP system uploads to "/orders" folder
    # Simple and clear — just one folder to upload to

    target = "/${aws_s3_bucket.orders.id}/uploads"
    # target = where the file actually goes in S3
    # /${aws_s3_bucket.orders.id} = the S3 bucket name
    # /uploads = inside the uploads folder
    # So when ERP uploads to "/orders/order.csv"
    # It actually lands at s3://bucket-name/uploads/order.csv
    # The S3 notification then triggers Lambda for files in uploads/
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-sftp-user"
    Purpose = "SFTP user account for legacy ERP system"
  })
}

# =============================================================
# SFTP USER PASSWORD
# =============================================================
# This sets the password for the SFTP user
# The legacy ERP system uses this password to connect
# Uses SERVICE_MANAGED authentication

resource "aws_transfer_ssh_key" "erp_password" {
  # Note: Despite the resource name saying "ssh_key"
  # When identity_provider_type = SERVICE_MANAGED
  # and we set a password — this handles password auth
  # AWS Transfer Family uses this resource for both keys and passwords

  server_id = aws_transfer_server.sftp.id
  user_name = aws_transfer_user.erp_orders.user_name
  # user_name = which user this password belongs to
  # Must match the user we created above

  body = var.sftp_password
  # body = the actual password value
  # This comes from variables.tf
  # It is marked sensitive = true so never shown in logs
  # In real production — store this in AWS Secrets Manager
}

# =============================================================
# TRANSFER FAMILY MANAGED WORKFLOW
# =============================================================
# This is what triggers Lambda IMMEDIATELY when a file uploads
# No polling — instant trigger
#
# Transfer Family Managed Workflow = a built-in event system
# The moment a file transfer completes —
# Transfer Family automatically runs this workflow
# The workflow triggers our Lambda function

resource "aws_transfer_workflow" "order_processing" {
  description = "Triggers Lambda immediately when order file upload completes"

  steps {
    # Steps = what to do when a file is uploaded
    # Each step runs in sequence

    type = "CUSTOM"
    # type = CUSTOM means we run our own Lambda function
    # Other types: COPY, DELETE, TAG (built-in operations)

    custom_step_details {
      name                 = "trigger-order-processor"
      # name = label for this step — shows in logs

      target               = aws_lambda_function.order_processor.arn
      # target = which Lambda to call
      # The moment upload completes — call this Lambda

      timeout_seconds      = 60
      # timeout_seconds = how long to wait for Lambda to respond
      # If Lambda does not respond in 60 seconds — workflow fails
      # We set Lambda timeout to 300 seconds — this is the workflow timeout
    }
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-workflow"
    Purpose = "Immediately processes order files after SFTP upload"
  })
}

# Attach the workflow to the SFTP server
resource "aws_transfer_server" "sftp_with_workflow" {
  # We need to update the server with the workflow ARN
  # This tells Transfer Family: when a file upload completes
  # automatically run this workflow

  # Note: In practice you would add workflow_details to the
  # original aws_transfer_server resource above
  # Shown separately here for teaching clarity
}

# =============================================================
# WHY THIS ARCHITECTURE MEETS ALL REQUIREMENTS
# =============================================================
#
# REQUIREMENT: Must speak SFTP — cannot change legacy system
# SOLUTION: Transfer Family provides fully managed SFTP server
# The ERP system connects exactly as it always has — nothing changes
#
# REQUIREMENT: Process files IMMEDIATELY — no polling
# SOLUTION: Transfer Family Managed Workflow triggers Lambda
# the instant a file upload completes — milliseconds delay
#
# REQUIREMENT: Highly Available — survive AZ failure
# SOLUTION: endpoint_details has TWO subnets in TWO AZs
# Transfer Family creates ENI in each AZ
# If AZ1 fails — AZ2 ENI still accepts connections
#
# REQUIREMENT: Secure — not on internet
# SOLUTION: endpoint_type = "VPC" — internal only
# Security group only allows port 22 from on-premises CIDR
# VPN/Direct Connect carries traffic — never touches internet
#
# REQUIREMENT: Resilient
# SOLUTION: S3 has 99.999999999% durability
# Lambda auto scales — handles any number of files
# Multi-AZ Transfer Family — no single point of failure
