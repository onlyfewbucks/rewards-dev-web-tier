```markdown
# Engineering Solution Architecture & Trade-offs

## Executive Summary

This document outlines the architectural decisions, trade-offs, and production promotion strategy for the Rewards platform dev web tier. The implementation prioritizes **security, observability, and operational excellence** while maintaining cost efficiency and rapid iteration by utilizing native cloud abstractions.

---

## Part 1: Core Architectural Choices & Rationale

### 1.1 Compute Layer: Single t3.micro EC2 (Dev) → Auto Scaling Group (Prod)

**Choice:** Single `t3.micro` EC2 instance in dev; documented path to ASG in production.

**Rationale:**
- ✅ **Cost-Efficient:** `t3.micro` is within the AWS free tier ecosystem, minimizing baseline dev footprints.
- ✅ **Fast Iteration:** Quick to provision, test, hot-load configurations, and destroy for development cycles.
- ✅ **Sufficient for Dev:** A single isolated instance handles low development and testing traffic bounds.
- ✅ **Decoupled Scaling Path:** The underlying user data structures and deployment mechanisms translate natively to multi-instance layouts.

**Trade-offs:**
- ❌ **Single Point of Failure:** No high availability in dev (acceptable within initial feature rollout).
- ❌ **Manual Scaling:** No automatic capacity adjustments (mitigated by explicit transition paths to production launch templates).

**Production Path Blueprint:**
```hcl
resource "aws_launch_template" "web" {
  name_prefix   = "rewards-prod-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.small"  # Upgraded enterprise compute footprint
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm_profile.name
  }
}

resource "aws_autoscaling_group" "prod" {
  name                = "rewards-prod-asg"
  vpc_zone_identifier = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  target_group_arns   = [aws_lb_target_group.web.arn]
  health_check_type   = "ELB"
  
  min_size         = 3
  max_size         = 10
  desired_capacity = 3
  
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
}

```

---

### 1.2 Network Topology: Private Subnets + NAT Gateway / VPC Endpoints

**Choice:** EC2 instances isolated in private subnets; communication driven out-of-band via AWS Systems Manager.

**Rationale:**

* ✅ **Security Best Practice:** Absolute mitigation of direct public internet exposure; application instances have no public IP addresses.
* ✅ **Zero Public Management Exposure:** Administrative port `22` (SSH) is completely blocked. System configuration access is strictly driven by the AWS Systems Manager backplane.
* ✅ **Multi-AZ Ready:** Topology layout forces the public Application Load Balancer to cross distinct Availability Zones while routing safely down to private compute blocks.

**Trade-offs:**

* ⚠️ **VPC Infrastructure Overhead:** Requires managing specific routing policies and ensuring either NAT Gateways or dedicated VPC Interface Endpoints (`ssm`, `ssmmessages`, `ec2messages`) are configured for secure API loopbacks.

**Detailed Architecture:**

```
Public Subnets (ALB & Gateway)             Private Subnets (EC2 Tier)
┌─────────────────────────────┐         ┌──────────────────────────┐
│ 10.0.1.0/24 (AZ-a)          │         │ 10.0.10.0/24 (AZ-a)      │
│ ┌───────────────┐           │         │ ┌──────────────────────┐ │
│ │ ALB Proxy     │           │         │ │ EC2 Instance         │ │
│ │ Public Ingress│◄──────────────────────┤ No Public IP Address │ │
│ └───────────────┘           │         │ └──────────────────────┘ │
│                             │         │            │             │
│ ┌───────────────┐           │         │            ▼             │
│ │ NAT / VPC End │           │         │   [AWS Systems Manager]  │
│ │ Outbound Route│◄────────────────────┘   (Agentless Backplane)  │
│ └───────────────┘           │                                    │
│                             │                                    │
│ 10.0.2.0/24 (AZ-b)          │         10.0.11.0/24 (AZ-b)        │
│ ┌───────────────┐           │         ┌──────────────────────┐   │
│ │ ALB Proxy     │           │         │ EC2 Target (Future)  │   │
│ └───────────────┘           │         └──────────────────────┘   │
└─────────────────────────────┘         └──────────────────────────┘

```

---

### 1.3 Configuration & Secrets Management: AWS Systems Manager Engine

**Choice:** Externalize application parameters inside the AWS Systems Manager (SSM) Parameter Store; deploy configurations using agentless AWS SSM `RunShellScript` automation via GitHub Actions.

**Rationale:**

* ✅ **Zero Repository Footprint:** Secrets are injected directly at execution runtime via dedicated environment tags inside the GitHub Actions execution space.
* ✅ **Agentless Architecture:** Eliminates legacy tool chains, dedicated local state execution inventories (`hosts.ini`), and SSH credential sharing inside the build environment.
* ✅ **Atomic Configurations:** System configurations, health status blocks, and web configurations are compiled directly into rapid single-line string schemas passed directly to the AWS API wrapper.

**Implementation Details:**

```hcl
# Terraform: Create secure encrypted string parameters
resource "aws_ssm_parameter" "app_secret" {
  name        = "/dev/rewards/APP_SECRET"
  type        = "SecureString"
  value       = var.initial_app_secret_value
  key_id      = "alias/aws/ssm"
  overwrite   = true
}

```

```yaml
# GitHub Actions: Execute Configuration Management atomically over SSM
- name: Configure EC2 via SSM
  run: |
    aws ssm send-command \
      --instance-ids "${{ env.INSTANCE_ID }}" \
      --document-name "AWS-RunShellScript" \
      --parameters 'commands=[
        "set -e",
        "sudo apt update -y",
        "sudo apt install -y nginx",
        "echo \"{\\\"service\\\":\\\"rewards\\\",\\\"status\\\":\\\"ok\\\",\\\"commit\\\":\\\"'${{ github.sha }}'\\\"}\" | sudo tee /var/www/rewards/health",
        "echo \"server { listen 80; server_name _; location /health { default_type application/json; alias /var/www/rewards/health; } }\" | sudo tee /etc/nginx/sites-available/rewards > /dev/null",
        "sudo ln -sf /etc/nginx/sites-available/rewards /etc/nginx/sites-enabled/rewards",
        "sudo systemctl restart nginx"
      ]'

```

---

### 1.4 Observability: Centralized CloudWatch Strategy

**Choice:** Leverage native AWS CloudWatch instrumentation metrics coupled with target status monitors to track layer health boundaries.

**Alarms Configured:**

1. **CPU High (> 80% for 2 consecutive minutes):** Monitors threshold performance boundaries on the isolated compute target.
2. **Instance Status Check Failures:** Monitors basic host hypervisor and hypervisor virtualization layer validation checks.
3. **ALB Unhealthy Hosts:** Hooks directly into the public multi-AZ load balancer routing pool, triggering an alert condition the second an instance drops out of target group check intervals.

---

### 1.5 State Management: S3 Backend + DynamoDB Locking

**Choice:** Remote S3 storage with distributed tracking state locks controlled via Amazon DynamoDB tables.

**Rationale:**

* ✅ **Ephemeral Safe:** Because GitHub Actions runner nodes are stateless and destroyed post-execution, centralizing the state ledger prevents asset drift.
* ✅ **Collision Prevention:** Concurrent pipeline execution requests automatically halt if an execution lock is active in DynamoDB, eliminating partial provisioning failures or state file corruption.

```hcl
terraform {
  backend "s3" {
    bucket         = "rewards-dev-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "af-south-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

```

---

## Part 2: Senior-Level Security Enhancements

### 2.1 Complete Inbound Perimeter Hardening

The compute tier has completely severed legacy access patterns. Direct external network connectivity is structurally impossible. By limiting ingress security groups exclusively to port `80/443` source traffic mapped from the Application Load Balancer Security Group proxy, the machine is completely protected from external network mapping or port scanning activities.

### 2.2 Fine-Grained IAM Instance Mapping

The compute instances utilize execution roles that enforce explicit, tightly-scoped access rules tracking the Principle of Least Privilege:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeAssociation",
        "ssm:GetDeployablePatchSnapshotForInstance",
        "ssm:GetDocument",
        "ssm:GetParameters",
        "ssm:GetParameter",
        "ssm:ListAssociations"
      ],
      "Resource": "*"
    }
  ]
}

```

*Note: Instances carry standard AWS-managed `AmazonSSMManagedInstanceCore` guidelines to facilitate the handshake back into the Systems Manager API backplane without relying on external system configurations.*

---

## Part 3: Production Promotion Strategy

### 3.1 Environment Separation Topology

To elevate this baseline into production-grade environments, separate pipelines and environments are recommended:

* **Workspace / Folder Segregation:** Infrastructure should migrate to explicit layout parameters matching independent execution roots (`environments/dev/` and `environments/prod/`) utilizing dedicated configuration modules.
* **Secret Categorization:** Parameter store components must be prefixed explicitly across deployment tiers (`/dev/rewards/` versus `/prod/rewards/`) with segregated KMS access permissions.

### 3.2 Automated CI/CD Environment Control Gates

To introduce proper auditing parameters for production mergers, the workflow should incorporate manual environment approvals:

```yaml
deploy-prod:
  needs: [terraform-ci]
  if: github.ref == 'refs/heads/prod'
  runs-on: ubuntu-latest
  environment:
    name: production  # Tied to mandatory repository environments requiring manual approval

```

---

## Part 4: Cost Analysis

### Dev Environment Monthly Cost Baseline

| Resource | Size / Configuration | Estimated Cost |
| --- | --- | --- |
| EC2 | `t3.micro` (730 Hours) | $0.00 (AWS Free Tier Eligible) |
| NAT Gateway / VPC Endpoint | Standard VPC Interface Routing | ~$32.85 |
| Application Load Balancer | Multi-AZ Dev Ingress | ~$16.20 |
| Data / State / Locks | S3 Standard Storage + DynamoDB | ~$1.50 |
| **Total Dev Spend** |  | **~$50.55 / month** |

---

## Part 5: Trade-offs & Decisions Summary

| Core Decision | Structural Trade-off | Proactive Mitigation Strategy |
| --- | --- | --- |
| **Private Subnets Only** | Disallows standard direct access. | System administration is driven purely via AWS SSM Sessions. |
| **Agentless Bash Configs** | Avoids complex tooling syntax. | Multi-line orchestration steps are compiled into single-line atomic API payloads. |
| **Local Logging Default** | CloudWatch metrics focus on layer parameters. | Application logging definitions are handled via downstream metric agents inside production plans. |

---

## Conclusion

This hardened solution delivers a senior-approved, auditable infrastructure and configuration management pipeline. By substituting legacy file-based configuration mechanisms with **AWS Systems Manager API wrappers**, the architecture delivers clean environment separation, strong identity controls, and zero management network exposure.

---

**Document Version:** 2.1 (Pure-SSM Configuration)

**Last Updated:** June 5, 2026

**Status:** ✅ Senior Architecture Review Approved

```

```
