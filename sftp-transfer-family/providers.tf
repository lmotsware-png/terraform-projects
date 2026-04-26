# =============================================================
# PROVIDERS.TF
# =============================================================
# This file tells Terraform:
# 1. WHICH cloud to use (AWS)
# 2. WHICH region to build in
# 3. WHICH version of Terraform tools to use
#
# Think of it like the first page of a contract
# It says WHO is doing the work and WHERE
# =============================================================

# This block tells Terraform which plugins it needs to download
# When you run "terraform init" — Terraform reads this and
# downloads the AWS plugin automatically
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # source = where to download the plugin from
      # hashicorp is the company that makes Terraform
      # aws is the plugin name

      version = "~> 5.0"
      # version = which version to use
      # ~> 5.0 means "use version 5.0 or higher but stay on version 5"
      # This protects you from breaking changes in future versions
    }
  }

  required_version = ">= 1.0"
  # This says your Terraform tool itself must be version 1.0 or higher
  # Protects against someone running very old Terraform
}

# This is the main AWS provider configuration
# It tells Terraform to build everything in Cape Town
provider "aws" {
  region = var.aws_region
  # var.aws_region means — get this value from variables.tf
  # We do not hardcode "af-south-1" here
  # We reference a variable so it is easy to change later
}

