```markdown
# Infrastructure & Configuration Automation Pipeline

This repository contains a fully automated, production-grade Infrastructure as Code (IaC) and Configuration Management pipeline designed to provision and configure a highly available, secure, and observable development web tier on AWS.

The entire rollout lifecycle—from syntax validation and linting to infrastructure provisioning, out-of-band secrets management, and agentless server orchestration—is driven entirely via **GitHub Actions**.

---

## 🏗️ Architectural Overview

The architecture is engineered to balance corporate security paradigms, system high availability, and operational observability while strictly avoiding unnecessary cloud overhead (such as high-cost NAT Gateways) within a development footprint by leveraging AWS Systems Manager (SSM).

### Core Structural Layout

* **Isolated Network (VPC):** A dedicated VPC (`10.0.0.0/16`) split across distinct Availability Zones via public subnets (for the Application Load Balancer prerequisites) and highly secure **private subnets** for the compute tier.
* **Layer 4/7 Security Hardening (Zero SSH):** The compute instance is fully isolated within a private subnet. It has **no public IP address and blocks all inbound public traffic (including port 22/SSH)**. It accepts incoming HTTP traffic (Layer 7) *only* when routed directly from the Application Load Balancer's (ALB) security group proxy.
* **Agentless Remote Configuration:** Instead of legacy SSH keys, administrative configuration and package deployments are securely orchestrated out-of-band via the **AWS Systems Manager (SSM) RunShellScript** API wrapper. 
* **The Runtime Engine:** Native **NGINX** serves the production-grade reverse-proxy web tier. It runs natively out-of-the-box, functions with negligible resource overhead, handles host restarts cleanly via `systemd`, and exposes a secure JSON `/health` telemetry endpoint.

---

## 🚀 The CI/CD GitOps Pipeline

The automation lifecycle is split into two deterministic verification phases driven by GitHub Actions (`.github/workflows/deploy.yml`):

### Phase 1: Continuous Integration (PR Verification)

Triggered on every Pull Request to the `main` branch:

1. **Code Quality Enforcement:** Executes `terraform fmt -check` to ensure the codebase respects strict, canonical spacing layout styling.
2. **Speculative Execution Plan:** Runs `terraform init` and `terraform plan` against the AWS account, creating a visible artifact of impending architectural changes before code review approval.

### Phase 2: Continuous Deployment (Trunk Merges)

Triggered automatically only when changes are securely merged into `main`:

1. **Infrastructure Application:** Directs Terraform to stand up or update the target AWS architecture topology.
2. **State Output Ingestion:** Dynamically queries and exports critical provisioned metadata (such as the generated target `INSTANCE_ID` and public `ALB_URL`) straight into the runner's ephemeral pipeline environment.
3. **SSM Orchestration Engine:** The runner calls the AWS SSM API to trigger an automated shell payload directly on the private EC2 target. This bootstrap sequence:
   * Updates package registries and installs `nginx`.
   * Provisions a localized web root directory.
   * Dynamically constructs an internal JSON health state file injecting metadata such as the active `$GITHUB_SHA` commit context.
   * Compiles and hot-loads a modular NGINX server block configuration.
4. **End-to-End Delivery Smoke Verification:** Executes an automated `curl` validation suite directly against the live, public ALB DNS endpoint string to verify successful routing and application runtime visibility before marking the pipeline run as successful.

---

## 🛠️ Getting Started & Local Usage

### Prerequisites

* Terraform `>= 1.8.0`
* AWS CLI configured with appropriate administrator credentials.
* **AWS SSM Infrastructure Prerequisites:** Ensure your target VPC contains SSM interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) or an available NAT gateway to allow the private EC2 instance to poll the AWS Systems Manager API.

### File Structure

```text
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions multi-stage SSM automation engine
└── terraform/
    ├── main.tf                 # Primary AWS infrastructure resource blueprints (VPC, EC2, ALB, IAM)
    ├── variables.tf            # Input configuration variables (ACM Certificates, Secrets)
    └── outputs.tf              # Dynamic resource string exposures (ALB DNS, Instance ID)

```

### Local Provisioning Sequence

If you wish to execute or test the infrastructure blueprint locally outside the automated runner environment, use the following sequence:

```bash
# 1. Initialize and download provider plugins
cd terraform
terraform init

# 2. Review structural execution plans
terraform plan -var="aws_key_pair_name=your-key"

# 3. Apply changes and spin up infrastructure
terraform apply -auto-approve -var="aws_key_pair_name=your-key"

```

---

## 📈 Observability & Production Scaling Path

### Active Guardrails

The infrastructure is actively monitored out-of-the-box by a CloudWatch metric alarm (`aws_cloudwatch_metric_alarm.cpu_high`). If the compute layer encounters sustained stress exceeding an 80% CPU usage threshold over consecutive evaluation windows, an alarm state triggers to notify operations of tier degradation.

### Enterprise Production Blueprint

To transition this development footprint into a high-scale, multi-tier production environment, the following architectural upgrades are recommended:

1. **State Externalization:** Migrate the local state engine to a secure, remote backend (such as an AWS S3 bucket with state-locking managed via DynamoDB tables).
2. **Elastic Scaling:** Replace the standalone `aws_instance` compute primitive with an **Auto Scaling Group (ASG)** managed behind the Load Balancer to absorb volatile consumer traffic spikes automatically.
3. **Advanced SSM Compliance:** Enforce explicit AWS IAM Session Manager logging across all nodes to provide completely immutable command histories and audit trails for internal systems access.

```

```
