```markdown
# Rewards Platform Dev Web Tier - Senior Level Hardened

This repository contains a **production-hardened, fully automated Infrastructure as Code (IaC) and Configuration Management pipeline** designed to provision and configure a secure, highly available web tier for the Rewards platform.

The entire rollout lifecycle—from syntax validation and linting to infrastructure provisioning, out-of-band secrets management, centralized logging, and server orchestration—is driven entirely via **GitHub Actions** and agentless **AWS Systems Manager (SSM)** execution.

---

## 🔐 Security Enhancements (vs. Original)

This hardened version implements senior-level security and operational best practices:

- ✅ **EC2 in Private Subnets** - Eliminates direct internet exposure; access via Systems Manager Session Manager.
- ✅ **Zero-SSH Operational Perimeter** - Port 22 is completely blocked; entirely eliminates private key distribution, rotation risks, and host exposure.
- ✅ **Agentless Remote Configuration** - Replaces heavy configuration runtimes with clean, atomic AWS SSM `RunShellScript` API pipelines.
- ✅ **NAT Gateway / VPC Endpoints** - Enables secure communication with AWS service endpoints and controlled outbound connectivity.
- ✅ **HTTPS/TLS Support** - HTTP redirects to HTTPS via Application Load Balancer; requires an ACM certificate.
- ✅ **Restricted Security Groups** - Ingress parameters strictly tied to the Application Load Balancer Security Group proxy.
- ✅ **IAM Roles & Policies** - Fine-grained permissions matching strict Principle of Least Privilege for EC2, SSM, and CloudWatch.
- ✅ **S3 State Backend with DynamoDB Locking** - Prevents concurrent state overwrite and data corruption.
- ✅ **IMDSv2 Enforcement** - Hardened EC2 metadata access limits.
- ✅ **Terraform Input Validation** - Catches configuration and schema errors before deployment.
- ✅ **GitHub Actions Hardening** - Secret masking, secure environment variables, and automated concurrency control.

---

## 🏗️ Architectural Overview

### Network Architecture


```

```
                Internet
                   ↓
         [ALB - Public Subnets]
         (Multi-AZ: 10.0.1.0/24, 10.0.2.0/24)
               ↙       ↘
    [Private Subnet 1a]   [Private Subnet 1b]
    (10.0.10.0/24)        (10.0.11.0/24)
          ↓                     ↓
    [EC2 Instance]       [EC2 Instance]
   (No Public IP)        (No Public IP)
          ↓                     ↓
    [NAT Gateway in Public Subnet 1a / VPC Endpoints]

```

```

### Core Components

- **Isolated Network (VPC):** Dedicated VPC (`10.0.0.0/16`) with public subnets for the ALB/NAT Gateway and private subnets for EC2 instances across multiple Availability Zones.
- **Layer 7 Security Hardening:** The Application Load Balancer completely isolates the compute layer. EC2 instances accept traffic **only** from the ALB security group. Direct external internet paths are impossible. 
- **Agentless Orchestration Engine:** Instead of deploying custom configuration software or handling loose SSH keypairs, administrative bootstrap management is handled natively out-of-band via **AWS Systems Manager (SSM) RunShellScript**.
- **Runtime Engine:** Native **NGINX** serves the production-grade reverse-proxy web tier. It runs natively, features minimal resource overhead, and handles host restarts cleanly via `systemd` while exposing a secure `/health` JSON telemetry endpoint.
- **Out-of-Band Secrets Management:** Runtime tokens and parameters are externalized in the AWS Systems Manager Parameter Store as encrypted strings, mapped directly into the environment via target IAM Instance Profiles.
- **State Backend:** S3 + DynamoDB for safe team deployments. Remote state prevents local overwrite issues, while DynamoDB locks prevent concurrent execution conflicts.

---

## 🚀 The CI/CD GitOps Pipeline

The automation lifecycle is split into two deterministic verification phases driven by GitHub Actions (`.github/workflows/deploy.yaml`):

### Phase 1: Continuous Integration (PR Verification)

Triggered on every Pull Request to the `main` branch:

1. **Code Quality Enforcement:** `terraform fmt -check` ensures canonical code layout styling.
2. **Configuration Validation:** `terraform validate` catches syntactic and provider schema errors early.
3. **Speculative Execution Plan:** `terraform plan` outputs a visible preview of impending infrastructure changes for review.
4. **Concurrency Control:** Cancels overlapping workflow runs to protect state locks.

### Phase 2: Continuous Deployment (Main Branch Merge)

Triggered automatically when changes are merged to `main`:

1. **Infrastructure Application:** Directs Terraform to stand up or update the target AWS architecture topology.
2. **State Output Ingestion:** Queries and exports critical provisioned metadata (such as the target `INSTANCE_ID` and public `ALB_URL`) straight into the runner's ephemeral environment.
3. **SSM Native Configuration:** The runner calls the AWS SSM API to fire an atomic script payload directly on the private EC2 target. This bootstrap sequence updates system registries, installs `nginx`, maps the active `$GITHUB_SHA` context into a JSON health telemetry payload, and hot-loads a modular NGINX server block configuration.
4. **End-to-End Delivery Smoke Verification:** Executes an automated `curl` validation suite directly against the live, public ALB DNS endpoint to verify system accessibility and successful routing before marking the run as successful.

---
## 🛠️ Prerequisites & Setup

### Local Prerequisites

- Terraform `>= 1.8.0`
- AWS CLI configured with appropriate administrator credentials.
- **VPC Configuration:** Interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) or an active NAT gateway attached to your private subnets to allow EC2 instances to pull payloads from the AWS Systems Manager API.

### AWS Setup (One-Time)

1. **Create S3 bucket for Terraform state:**
   ```bash
   aws s3api create-bucket \
     --bucket rewards-dev-terraform-state \
     --region af-south-1 \
     --create-bucket-configuration LocationConstraint=af-south-1
   
   aws s3api put-bucket-versioning \
     --bucket rewards-dev-terraform-state \
     --versioning-configuration Status=Enabled
   
   aws s3api put-bucket-encryption \
     --bucket rewards-dev-terraform-state \
     --server-side-encryption-configuration '{
       "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
     }'

```

2. **Create DynamoDB table for state locking:**
```bash
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region af-south-1

```



### GitHub Secrets Setup

Set these secrets in repository settings:

| Secret | Example | Notes |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` | IAM user with EC2, ALB, SSM, and S3 permissions |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` | Encrypted pipeline deployment credential |
| `AWS_DEFAULT_REGION` | `af-south-1` | Must match S3 bucket target region |
| `ACM_CERTIFICATE_ARN` | `arn:aws:acm:af-south-1:123456789:certificate/...` | ACM cert ARN for HTTPS listeners |
| `APP_SECRET` | `SuperSecureRandomString123!@#` | Extracted out-of-band into Parameter Store |
| `AWS_KEY_PAIR_NAME` | `rewards-dev-key` | Optional backup fallback identifier |

---

## 📂 File Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yaml                 # GitHub Actions CI/CD pipeline (SSM Engine)
├── .gitignore                          # Terraform ignore patterns
├── README.md                           # This file
├── SOLUTION.md                         # Architecture & trade-off documentation
└── terraform/
    ├── main.tf                         # VPC, ALB, EC2, IAM roles, and state backend definitions
    ├── variables.tf                    # Input variables with validation rules
    └── output.tf                       # Dynamic resource exposures (ALB DNS, Instance ID)

```

---

## 🚀 Getting Started

### Local Development (Non-Automated)

If you want to plan or test structural modifications locally before pushing to GitHub:

```bash
# 1. Navigate to Terraform directory
cd terraform

# 2. Initialize Terraform (S3 Backend integration)
terraform init

# 3. Plan infrastructure changes
terraform plan -var="aws_key_pair_name=dummy-key" -out=tfplan

# 4. Apply changes
terraform apply tfplan

```

### Automated Deployment Sequence

1. **Create a feature branch:**
```bash
git checkout -b feature/harden-nginx-config

```


2. **Commit changes:**
```bash
git add terraform/
git commit -m "feat: adjust NGINX internal health block schema"

```


3. **Push and create Pull Request:**
```bash
git push origin feature/harden-nginx-config

```


4. **Review Terraform plan in PR** -> GitHub Actions logs will append a speculative architectural change report.
5. **Merge to main** -> Pipeline hooks automatically handle execution, deployment, out-of-band SSM configuration routing, and end-to-end smoke testing.

---

## 📊 Observability & Monitoring

### Centralized Shell Verification

Since instances are in a secure private subnet, interact with instances securely without an SSH key via the AWS SSM CLI plug-in:

```bash
# Start a interactive shell session inside the private subnet instance
aws ssm start-session --target i-1234567890abcdef0

```

### CloudWatch Alarms

Three default cloud alarms monitor the infrastructure health parameters:

1. **CPU High:** Triggers if resource utilization exceeds 80% for 2 consecutive minutes.
2. **Status Check Failed:** Triggers if the hardware host or compute virtualization layer fails structural hypervisor metrics.
3. **ALB Unhealthy Hosts:** Triggers immediately if the target instance drops out of active target group verification windows.

---

## 🧹 Cleanup Instructions

To tear down all resources and prevent unnecessary AWS charges:

```bash
# 1. Destroy core infrastructure components
terraform -chdir=terraform destroy -auto-approve -var="aws_key_pair_name=dummy-key"

# 2. Delete S3 state bucket tracking files
aws s3 rm s3://rewards-dev-terraform-state --recursive
aws s3api delete-bucket --bucket rewards-dev-terraform-state --region af-south-1

# 3. Delete DynamoDB locks table
aws dynamodb delete-table --table-name terraform-locks --region af-south-1

```

---

## 📈 Production Promotion Strategy

To scale this development baseline into an isolated enterprise framework:

1. **State Workspace Segregation:** Utilize distinct remote S3 prefixes or physical environments subdirectories (`environments/dev/` vs `environments/prod/`).
2. **Multi-AZ Auto Scaling:** Replace individual `aws_instance` primitives with an Elastic **Auto Scaling Group (ASG)** spanning at least two private subnets underneath the existing ALB target paths.
3. **CI/CD Manual Approval Gates:** Implement specialized deployment environment protections inside GitHub Actions requiring mandatory sign-off approvals before changes are allowed to strike live Production infrastructure targets.

---

## 🔍 Troubleshooting

### SSM Payload / Pipeline Configuration Errors

If your pipeline hangs or drops out during the `Configure EC2 via SSM` sequence, verify the target instance profile:

1. Ensure the EC2 instance carries an IAM role containing the managed policy `AmazonSSMManagedInstanceCore`.
2. Confirm that the private subnet can resolve the AWS SSM API endpoints. Execute `aws ssm describe-instance-information` locally to verify if the server is checking in correctly.

---

**Last Updated:** June 5, 2026

**Maintained By:** Cloud Infrastructure Team

**Status:** ✅ Production-Ready (Zero-SSH Perimeter)

```

```
