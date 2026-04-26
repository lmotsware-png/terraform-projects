# =============================================================
# OUTPUTS.TF
# =============================================================
# Outputs are values Terraform displays after building everything
# Like a summary report at the end
#
# After "terraform apply" completes — outputs show:
# - The SFTP server endpoint address (give this to ERP team)
# - The S3 bucket name (for reference)
# - The Lambda function name (for monitoring)
#
# Outputs are also useful when you have multiple Terraform projects
# One project can read the outputs of another
# =============================================================

output "sftp_server_id" {
  description = "The ID of the Transfer Family SFTP server"
  value       = aws_transfer_server.sftp.id
  # After terraform apply — shows: sftp_server_id = "s-1234567890abcdef0"
}

output "sftp_server_endpoint" {
  description = "The endpoint address the ERP system uses to connect — give this to the ERP/network team"
  value       = aws_transfer_server.sftp.endpoint
  # This is the address the legacy ERP system connects to via SFTP
  # Format: s-1234567890abcdef0.server.transfer.af-south-1.amazonaws.com
  # Give this to whoever configures the ERP system
}

output "sftp_username" {
  description = "The SFTP username the ERP system uses"
  value       = var.sftp_username
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket where order files are stored"
  value       = aws_s3_bucket.orders.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 orders bucket"
  value       = aws_s3_bucket.orders.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda order processor function"
  value       = aws_lambda_function.order_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda order processor function"
  value       = aws_lambda_function.order_processor.arn
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_az1_id" {
  description = "ID of private subnet in AZ1"
  value       = aws_subnet.private_az1.id
}

output "private_subnet_az2_id" {
  description = "ID of private subnet in AZ2"
  value       = aws_subnet.private_az2.id
}

output "cloudwatch_log_group_lambda" {
  description = "CloudWatch log group where Lambda logs appear — check here when troubleshooting"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "cloudwatch_log_group_transfer" {
  description = "CloudWatch log group for Transfer Family SFTP activity logs"
  value       = aws_cloudwatch_log_group.transfer_family.name
}

output "deployment_summary" {
  description = "Summary of what was deployed"
  value = <<-EOT
    ================================================
    SFTP Order Processing Infrastructure Deployed
    ================================================
    
    SFTP Server Endpoint: ${aws_transfer_server.sftp.endpoint}
    SFTP Username: ${var.sftp_username}
    
    S3 Bucket: ${aws_s3_bucket.orders.id}
    Upload folder: uploads/
    
    Lambda Function: ${aws_lambda_function.order_processor.function_name}
    
    VPC: ${aws_vpc.main.id}
    Region: ${var.aws_region}
    
    Next Steps:
    1. Give SFTP endpoint address to ERP/network team
    2. Configure VPN/Direct Connect to reach VPC
    3. Test SFTP connection from on-premises
    4. Monitor Lambda logs in CloudWatch
    ================================================
  EOT
}
