terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.80.0"
    }
  }
  # For the assignment, local state is used to keep things simple, 
  # but we document remote state in SOLUTION.md
  backend "local" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      environment = "dev"
      service     = "rewards"
      owner       = "candidate"
      cost_center = "payments"
    }
  }
}

# --- NETWORK LAYER ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "rewards-dev-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b" # ALB requires 2 AZs
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# --- SECURITY GROUPS ---
resource "aws_security_group" "alb" {
  name        = "rewards-dev-alb-sg"
  description = "Allow public HTTP traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web" {
  name        = "rewards-dev-web-sg"
  description = "Allow traffic from ALB and SSH for config"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In prod, lock this down or use SSM Session Manager
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = var.key_name

  tags = { Name = "rewards-dev-web-server" }
}

# --- LOAD BALANCER ---
resource "aws_lb" "external" {
  name               = "rewards-dev-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  overwrite          = true
}

resource "aws_lb_target_group" "web" {
  name      = "rewards-dev-tg"
  port      = 80
  protocol  = "HTTP"
  overwrite = true
  vpc_id    = aws_vpc.main.id

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
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = "80"
  protocol          = "HTTP"

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
  overite     = true
}

# --- OBSERVABILITY (BASIC METRICS / ALARMS) ---
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "rewards-dev-ec2-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors ec2 cpu utilization"

  dimensions = {
    InstanceId = aws_instance.web.id
  }
}
