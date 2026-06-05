output "alb_dns_name" {
  value       = aws_lb.external.dns_name
  description = "Public entry point for the application"
}

