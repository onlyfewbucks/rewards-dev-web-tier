variable "aws_region" {
  type        = string
  default     = "af-south-1"
  description = "AWS region for resource deployment"

  validation {
    condition     = length(var.aws_region) > 0
    error_message = "AWS region must not be empty."
  }
}

variable "acm_certificate_arn" {
  type        = string
  description = "ARN of ACM certificate for HTTPS listener (create in AWS Console first)"

  validation {
    condition     = can(regex("arn:aws:acm:", var.acm_certificate_arn))
    error_message = "Must be a valid ACM certificate ARN (e.g., arn:aws:acm:region:account:certificate/id)."
  }
}

variable "initial_app_secret_value" {
  type        = string
  sensitive   = true
  description = "Initial value for APP_SECRET stored in SSM Parameter Store"

  validation {
    condition     = length(var.initial_app_secret_value) >= 16
    error_message = "APP_SECRET must be at least 16 characters for adequate security."
  }
}
