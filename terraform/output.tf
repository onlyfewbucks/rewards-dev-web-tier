output "alb_dns_name" {
  value       = aws_lb.external.dns_name
  description = "Public entry point for the application"
}

output "instance_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Used by the Ansible inventory string in CI/CD"
}
