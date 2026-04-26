# =============================================================
# VARIABLES.TF
# =============================================================
# Variables are like settings you define ONCE at the top
# and use everywhere else in your code
#
# WHY use variables?
# Imagine you hardcode "af-south-1" in 20 different files
# One day you need to change region — you update 20 files
# With variables — you change it in ONE place here
# Everything else updates automatically
#
# STRUCTURE of every variable:
# variable "name_of_variable" {
#   description = "what is this for"    ← explains it to humans
#   type        = string/number/bool    ← what kind of value
#   default     = "some value"          ← value if not specified
# }
# =============================================================

# =============================================================
# GENERAL SETTINGS
# =============================================================

variable "aws_region" {
  description = "The AWS region where all resources will be built"
  type        = string
  default     = "af-south-1"
  # af-south-1 = Cape Town, South Africa
  # This is used in providers.tf as var.aws_region
}

variable "project_name" {
  description = "Name of this project — used as prefix for all resource names"
  type        = string
  default     = "woolworths-orders"
  # Every resource name will start with this
  # Example: woolworths-orders-sftp-server
  # Example: woolworths-orders-s3-bucket
  # Makes it easy to find all resources in AWS console
}

variable "environment" {
  description = "Which environment is this — production, staging, or dev"
  type        = string
  default     = "production"
  # Good practice to tag everything with environment
  # So you know which resources are live vs test
}

# =============================================================
# NETWORKING VARIABLES
# =============================================================

variable "vpc_cidr" {
  description = "The IP address range for the entire VPC"
  type        = string
  default     = "10.0.0.0/16"
  # /16 means we have 65,536 IP addresses available
  # From your CCNA — you know CIDR notation
  # 10.0.0.0 to 10.0.255.255 = all ours
}

variable "private_subnet_cidr_az1" {
  description = "IP range for private subnet in Availability Zone 1"
  type        = string
  default     = "10.0.1.0/24"
  # /24 means 256 IP addresses
  # 10.0.1.0 to 10.0.1.255
  # This is where our SFTP server ENI lives in AZ A
}

variable "private_subnet_cidr_az2" {
  description = "IP range for private subnet in Availability Zone 2"
  type        = string
  default     = "10.0.2.0/24"
  # 10.0.2.0 to 10.0.2.255
  # This is where our SFTP server ENI lives in AZ B
  # Different subnet = different AZ = high availability
}

variable "on_premises_cidr" {
  description = "The IP address range of the on-premises network (company office/data center)"
  type        = string
  default     = "192.168.1.0/24"
  # This is the IP range of Woolworths head office network
  # The security group will ONLY allow SFTP connections from this range
  # Nobody else on the internet can connect
  # In real life this would be your actual office network range
  # From your CCNA — 192.168.x.x is a private IP range
}

# =============================================================
# SFTP SERVER VARIABLES
# =============================================================

variable "sftp_username" {
  description = "The username the legacy ERP system uses to connect via SFTP"
  type        = string
  default     = "erp-orders-user"
  # This is the login name
  # The legacy ERP system connects with this username
  # Like a normal username on any system
}

variable "sftp_password" {
  description = "Password for SFTP user authentication"
  type        = string
  sensitive   = true
  # sensitive = true means Terraform will NEVER show this in logs
  # Even if you run terraform plan — password will show as (sensitive)
  # This protects your password from being exposed
  # NO default here — you must provide this when running terraform
  # Best practice: use environment variable or .tfvars file
}

# =============================================================
# S3 VARIABLES
# =============================================================

variable "s3_bucket_name" {
  description = "Name of the S3 bucket where uploaded order files will be stored"
  type        = string
  default     = "woolworths-orders-files"
  # S3 bucket names must be globally unique across ALL of AWS worldwide
  # We will add the account ID to make it unique in main configuration
}

# =============================================================
# LAMBDA VARIABLES
# =============================================================

variable "lambda_timeout" {
  description = "Maximum seconds Lambda function is allowed to run"
  type        = number
  default     = 300
  # 300 seconds = 5 minutes
  # If Lambda runs longer than this — it is automatically stopped
  # For processing order files 5 minutes is generous
  # Simple files might only take 30 seconds
}

variable "lambda_memory" {
  description = "How much RAM in MB to give the Lambda function"
  type        = number
  default     = 512
  # 512 MB of RAM
  # More RAM = faster execution = slightly more expensive
  # For processing CSV order files 512MB is more than enough
  # Lambda memory goes from 128MB up to 10,240MB
}

# =============================================================
# TAGS — Metadata for every resource
# =============================================================
# Tags are like labels you put on every resource
# They help you:
# - Find resources easily in AWS console
# - Track costs per project
# - Know who owns each resource
# - Understand the purpose of each resource

variable "common_tags" {
  description = "Tags applied to every single resource in this project"
  type        = map(string)
  # map(string) means a collection of key-value pairs
  # Like a dictionary — key = label name, value = label content

  default = {
    Project     = "woolworths-orders-sftp"
    Environment = "production"
    Owner       = "Lerato Motsware"
    ManagedBy   = "Terraform"
    Purpose     = "Legacy ERP SFTP to S3 file transfer"
    GitHub      = "github.com/Imotsware-png/terraform-projects"
  }
  # Every resource will have these tags
  # When you look at AWS console you immediately know:
  # - Which project this belongs to
  # - Who built it
  # - That it was built with Terraform
}
