terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.80.0"
    }
  }

  # Remote state backend for team collaboration and locking
  backend "s3" {
    bucket         = "rewards-dev-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "af-south-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      environment = "dev"
      service     = "rewards"
      owner       = "candidate"
      cost_center = "payments"
      managed_by  = "terraform"
    }
  }
}

# --- NETWORK LAYER ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "rewards-dev-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "rewards-dev-igw" }
}

# Public subnets for ALB and NAT Gateway
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "rewards-dev-public-1a" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "rewards-dev-public-1b" }
}

# Private subnets for EC2 instances (SECURITY REQUIREMENT)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "rewards-dev-private-1a" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "rewards-dev-private-1b" }
}

# NAT Gateway for outbound access from private subnets
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "rewards-dev-nat-eip" }

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
  tags          = { Name = "rewards-dev-nat-gw" }

  depends_on = [aws_internet_gateway.gw]
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "rewards-dev-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Private route table with NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "rewards-dev-private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# --- SECURITY GROUPS ---
resource "aws_security_group" "alb" {
  name        = "rewards-dev-alb-sg"
  description = "Allow public HTTP/HTTPS traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rewards-dev-alb-sg" }
}

resource "aws_security_group" "web" {
  name        = "rewards-dev-web-sg"
  description = "Allow traffic from ALB only (no direct SSH)"
  vpc_id      = aws_vpc.main.id

  # Ingress from ALB only
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Restricted egress: only allow necessary outbound traffic
  egress {
    description = "DNS (UDP 53)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP for package updates"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS for package updates and AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rewards-dev-web-sg" }
}

# --- IAM ROLE FOR EC2 (Systems Manager & SSM Parameter Access) ---
resource "aws_iam_role" "ec2_role" {
  name = "rewards-dev-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = { Name = "rewards-dev-ec2-role" }
}

# Attach SSM Session Manager policy
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach SSM Parameter Store read policy
resource "aws_iam_role_policy" "ssm_parameter_policy" {
  name = "rewards-dev-ssm-parameter-read"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/dev/rewards/*"
      }
    ]
  })
}

# CloudWatch Logs policy for log streaming
resource "aws_iam_role_policy" "cloudwatch_logs_policy" {
  name = "rewards-dev-cloudwatch-logs"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/ec2/rewards-dev*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "rewards-dev-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# --- COMPUTE LAYER ---
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_1.id # SECURITY: Private subnet
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false # SECURITY: No public IP

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # SECURITY: IMDSv2 only
    http_put_response_hop_limit = 1
  }

  monitoring = true # Enable detailed CloudWatch monitoring

  tags = { Name = "rewards-dev-web-server" }

  depends_on = [
    aws_nat_gateway.main,
    aws_iam_role_policy.cloudwatch_logs_policy
  ]
}

# --- LOAD BALANCER ---
resource "aws_lb" "external" {
  name               = "rewards-dev-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  enable_deletion_protection = false
  enable_http2               = true

  tags = { Name = "rewards-dev-alb" }
}

resource "aws_lb_target_group" "web" {
  name     = "rewards-dev-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "rewards-dev-tg" }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# HTTP listener with redirect to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener (requires ACM certificate in variables)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.external.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# --- SECRETS PROVISIONED OUTSIDE REPO ---
resource "aws_ssm_parameter" "app_secret" {
  name        = "/dev/rewards/APP_SECRET"
  description = "Application runtime secret managed out-of-band"
  type        = "SecureString"
  value       = var.initial_app_secret_value
  overwrite   = true

  tags = { Name = "rewards-dev-app-secret" }
}

# --- CLOUDWATCH LOGS ---
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/rewards-dev/application"
  retention_in_days = 30

  tags = { Name = "rewards-dev-app-logs" }
}

resource "aws_cloudwatch_log_stream" "app" {
  name           = "rewards-dev-stream"
  log_group_name = aws_cloudwatch_log_group.app.name
}

# --- OBSERVABILITY (METRICS & ALARMS) ---
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "rewards-dev-ec2-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alert when EC2 CPU exceeds 80%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.web.id
  }

  tags = { Name = "rewards-dev-cpu-alarm" }
}

resource "aws_cloudwatch_metric_alarm" "instance_status_check" {
  alarm_name          = "rewards-dev-ec2-status-check"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when EC2 status check fails"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.web.id
  }

  tags = { Name = "rewards-dev-status-alarm" }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "rewards-dev-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when ALB has unhealthy targets"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.external.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  tags = { Name = "rewards-dev-alb-alarm" }
}

# --- TERRAFORM STATE BACKEND SETUP (for first run) ---
# Note: Run `scripts/setup-state-backend.sh` before `terraform init`
# to create S3 bucket and DynamoDB table for state locking
