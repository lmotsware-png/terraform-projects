# =============================================================
# VARIABLES.TF
# =============================================================
# Variables are like settings you define ONCE and use everywhere
# Instead of hardcoding values in every file
# you define them here and reference them anywhere
#
# Think of it like a settings page on your phone
# You set your name once — it appears everywhere in the app
# =============================================================

# Your application name — used for naming all resources
variable "app_name" {
  description = "Name of your application"
  type        = string
  default     = "sabc-news"
}

# Environment — are we building production or test?
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

# =============================================================
# EC2 SETTINGS
# =============================================================

# The AMI is your server image — the snapshot of your OS
# This is the Amazon Linux 2 AMI for Cape Town region
# Remember — AMI IDs are different per region
variable "main_ami_id" {
  description = "AMI ID for main region EC2 instances"
  type        = string
  default     = "ami-0c1a7f89451184c8b"   # Amazon Linux 2 — Cape Town
}

# DR region has a different AMI ID for same OS
variable "dr_ami_id" {
  description = "AMI ID for DR region EC2 instances"
  type        = string
  default     = "ami-0d71ea30463e0ff49"   # Amazon Linux 2 — Ireland
}

# Main region runs LARGE instances — full production size
variable "main_instance_type" {
  description = "EC2 instance type for main region"
  type        = string
  default     = "m5.large"   # 2 CPU 8GB RAM — production size
}

# DR region runs SMALL instances — warm standby scaled down
# Remember the warm standby concept — scaled DOWN but fully functional
variable "dr_instance_type" {
  description = "EC2 instance type for DR region — scaled down"
  type        = string
  default     = "t3.small"   # 2 CPU 2GB RAM — minimal but running
}

# =============================================================
# AUTO SCALING SETTINGS
# =============================================================

# Main region auto scaling — handles full production traffic
variable "main_min_instances" {
  description = "Minimum EC2 instances in main region"
  type        = number
  default     = 2    # Always at least 2 running for high availability
}

variable "main_max_instances" {
  description = "Maximum EC2 instances in main region"
  type        = number
  default     = 10   # Scale up to 10 during high traffic
}

# DR region auto scaling — small during normal times
# Scales UP when disaster hits
variable "dr_min_instances" {
  description = "Minimum EC2 instances in DR region"
  type        = number
  default     = 1    # Only 1 running normally — warm standby
}

variable "dr_max_instances" {
  description = "Maximum EC2 instances in DR region"
  type        = number
  default     = 10   # Can scale to same as main when needed
}

# =============================================================
# DATABASE SETTINGS
# =============================================================

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "sabcnewsdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true   # sensitive = true means Terraform hides this in logs
  default     = "ChangeMe123!"
  # In real production you would use AWS Secrets Manager
  # Never hardcode passwords in real code
}

# Main region database — full production size
variable "main_db_instance_class" {
  description = "RDS instance size for main region"
  type        = string
  default     = "db.m5.large"   # Production size database
}

# DR region database — smaller replica
variable "dr_db_instance_class" {
  description = "RDS instance size for DR region"
  type        = string
  default     = "db.t3.medium"  # Smaller — warm standby size
}

# =============================================================
# ROUTE 53 SETTINGS
# =============================================================

variable "domain_name" {
  description = "Your website domain name"
  type        = string
  default     = "sabcnews.co.za"
}
