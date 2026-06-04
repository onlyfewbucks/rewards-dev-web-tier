output "alb_dns_name" {
  value       = aws_lb.external.dns_name
  description = "Public DNS name for ALB (use with HTTPS)"
}

output "alb_arn" {
  value       = aws_lb.external.arn
  description = "ARN of the Application Load Balancer"
}

output "instance_id" {
  value       = aws_instance.web.id
  description = "EC2 instance ID (access via Systems Manager Session Manager)"
}

output "cloudwatch_log_group" {
  value       = aws_cloudwatch_log_group.app.name
  description = "CloudWatch log group for application logs"
}

output "cleanup_instructions" {
  value = <<-EOT
    To clean up all resources:
    
    1. Remove S3 backend state:
       aws s3 rm s3://rewards-dev-terraform-state --recursive
    
    2. Delete DynamoDB locks table:
       aws dynamodb delete-table --table-name terraform-locks
    
    3. Destroy infrastructure:
       terraform -chdir=terraform destroy -auto-approve
    
    4. Clean up local state (after destroy):
       rm -rf terraform/.terraform terraform/terraform.tfstate* terraform/.terraform.lock.hcl
  EOT
  description = "Instructions for cleaning up all resources"
}
