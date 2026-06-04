This repository contains a fully automated, production-grade Infrastructure as Code (IaC) and Configuration Management pipeline designed to provision and configure a highly available, secure, and observable development web tier on AWS.

The entire rollout lifecycle—from syntax validation and linting to infrastructure provisioning, out-of-band secrets management, and server orchestration—is driven entirely via **GitHub Actions**.

---
## 🏗️ Architectural Overview

The architecture was engineered to balance corporate security paradigms, system high availability, and operational observability while strictly avoiding unnecessary cloud overhead (such as high-cost NAT Gateways) within a development footprint.

### Core Structural Layout

* **Isolated Network (VPC):** A dedicated VPC (`10.0.0.0/16`) split across two distinct Availability Zones via public subnets to satisfy Application Load Balancer (ALB) multi-AZ prerequisites.
* **Layer 4 Security Hardening:** The compute instance is isolated behind an application security group that **only** accepts incoming HTTP traffic (Layer 7) directly routed from the ALB's security group proxy. Direct public ingress is strictly limited to port `22` for administrative configuration.
* **The Runtime Engine:** Native **NGINX** was chosen to serve the production-grade reverse-proxy web tier. It runs natively out-of-the-box, functions with negligible resource overhead, and handles host restarts cleanly via systemd.
* **Out-of-Band Secrets Management:** Rather than introducing credential exposure risks inside source control, runtime tokens and application secrets are externalized in the **AWS Systems Manager (SSM) Parameter Store** as encrypted `SecureString` data types.

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
2. **Out-of-Band Secrets Ingestion:** The runner calls the regional AWS SSM Parameter Store directly using an IAM service principal role, fetching the decrypted application secret dynamically into an ephemeral pipeline environment variable.
3. **Ansible Configuration Engine:** Dynamically generates a runtime inventory containing the new compute target IP and fires an `ansible-playbook` run over SSH to handle package provisioning, system formatting, and secret file placement.
4. **End-to-End Delivery Smoke Verification:** Executes an automated `curl` validation suite directly against the live, public ALB DNS endpoint string to verify successful service delivery before marking the pipeline run as successful.

---

## 🛠️ Getting Started & Local Usage

### Prerequisites

* Terraform `>= 1.5.0`
* Ansible `>= 2.14`
* AWS CLI configured with appropriate administrator credentials.

### File Structure

```text
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions multi-stage automation engine
├── ansible/
│   ├── playbook.yml            # NGINX configuration and secret rendering playbook
│   └── templates/
│       └── index.html.j2       # Dynamic Jinja2 delivery template
└── terraform/
    ├── main.tf                 # Primary AWS infrastructure resource blueprints
    ├── variables.tf            # Input configuration variables
    └── outputs.tf              # Dynamic resource string exposures

```

### Local Provisioning Sequence

If you wish to execute or test the plan locally outside the automated runner environment, use the following sequence:

```bash
# 1. Initialize and download provider plugins
cd terraform
terraform init

# 2. Review structural execution plans
terraform plan

# 3. Apply changes and spin up infrastructure
terraform apply -auto-approve

```

---

## 📈 Observability & Production Scaling Path

### Active Guardrails

The infrastructure is actively monitored out-of-the-box by a CloudWatch metric alarm (`aws_cloudwatch_metric_alarm.cpu_high`). If the compute layer encounters sustained stress exceeding a 80% CPU usage threshold over consecutive evaluation windows, an alarm state triggers to notify operations of tier degradation.

### Enterprise Production Blueprint

To transition this development footprint into a high-scale, multi-tier production environment, the following architectural upgrades are recommended:

1. **State Externalization:** Migrate the local state engine to a secure, remote backend backend (such as an AWS S3 bucket with state-locking managed via DynamoDB tables).
2. **Elastic Scaling:** Replace the standalone `aws_instance` compute primitive with an **Auto Scaling Group (ASG)** managed behind the Load Balancer to absorb volatile consumer traffic spikes automatically.
3. **Strict Network Perimeter (Private Subnets):** Shift all compute tier targets entirely into private subnets, dropping external SSH access entirely, and utilize **AWS Systems Manager Session Manager** for fully audited, secure shell access. Upstream outbound updates would route securely via controlled NAT Gateways.
