variable "aws_region" {
  type    = string
  default = "af-south-1"
}

variable "key_name" {
  type        = string
  description = "SSH key pair name for access"
}

variable "initial_app_secret_value" {
  type      = string
  sensitive = true
}
