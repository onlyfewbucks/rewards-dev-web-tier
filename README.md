# Rewards Platform Dev Web Tier - Senior Level Hardened

This repository contains a **production-hardened, fully automated Infrastructure as Code (IaC) and Configuration Management pipeline** designed to provision and configure a secure, highly available web tier for the Rewards platform.

The entire rollout lifecycle—from syntax validation and linting to infrastructure provisioning, out-of-band secrets management, centralized logging, and server orchestration—is driven entirely via **GitHub Actions**.

---

## 🔐 Security Enhancements (vs. Original)

This hardened version implements senior-level security and operational best practices:

- ✅ **EC2 in Private Subnets** - Eliminates direct internet exposure; access via Systems Manager Session Manager
- ✅ **NAT Gateway** - Enables secure outbound connectivity from private subnets
- ✅ **HTTPS/TLS Support** - HTTP redirects to HTTPS; requires ACM certificate
- ✅ **Restricted Security Groups** - Egress rules limited to DNS, HTTP/HTTPS only
- ✅ **IAM Roles & Policies** - Fine-grained permissions for EC2, SSM, and CloudWatch
- ✅ **CloudWatch Centralized Logging** - Application and system logs streamed to CloudWatch Logs
- ✅ **Enhanced Observability** - CPU, status check, ALB health, disk, memory metrics
- ✅ **S3 State Backend with DynamoDB Locking** - Prevents concurrent state corruption
- ✅ **IMDSv2 Enforcement** - Hardened EC2 metadata access
- ✅ **Terraform Input Validation** - Catches configuration errors before deployment
- ✅ **GitHub Actions Hardening** - Secret masking, secure key handling, concurrency control
- ✅ **Ansible Security** - `no_log` for secrets, UFW firewall, NGINX hardening

---

## 🏗️ Architectural Overview

### Network Architecture

```
                    Internet
                       ↓
              [ALB - Public Subnets]
              (Multi-AZ: 10.0.1.0/24, 10.0.2.0/24)
                   ↙          ↘
        [Private Subnet 1a]   [Private Subnet 1b]
        (10.0.10.0/24)        (10.0.11.0/24)
              ↓                     ↓
        [EC2 Instance]       [EC2 Instance]
      (No Public IP)        (No Public IP)
              ↓                     ↓
        [NAT Gateway in Public Subnet 1a]
```

### Core Components

- **Isolated Network (VPC):** Dedicated VPC (`10.0.0.0/16`) with:
  - Public subnets for ALB and NAT Gateway (multi-AZ)
  - Private subnets for EC2 instances (multi-AZ)
  - Controlled egress for outbound connectivity

- **Layer 7 Security Hardening:** Application Load Balancer isolates compute layer:
  - EC2 instances accept traffic ONLY from ALB security group
  - Direct internet access impossible
  - SSH access via Systems Manager Session Manager (no SSH key exposure)

- **Runtime Engine:** NGINX serves production-grade reverse-proxy web tier:
  - Lightweight, efficient, production-tested
  - Auto-restarts via systemd across reboots
  - Hardened configuration (no server tokens, size limits)

- **Out-of-Band Secrets Management:** Runtime secrets externalized in AWS Systems Manager Parameter Store:
  - No credentials in source control
  - Encrypted at rest with KMS
  - Accessed via IAM roles (no long-lived credentials)

- **Centralized Logging:** CloudWatch Logs aggregates:
  - NGINX access and error logs
  - System logs (syslog)
  - Custom application metrics
  - 30-day retention (configurable)

- **State Backend:** S3 + DynamoDB for safe team deployments:
  - Remote state prevents local overwrite issues
  - DynamoDB locks prevent concurrent modifications
  - Encrypted at rest with encryption enabled

---

## 🚀 The CI/CD GitOps Pipeline

The automation lifecycle is split into two deterministic verification phases driven by GitHub Actions (`.github/workflows/deploy.yaml`):

### Phase 1: Continuous Integration (PR Verification)

Triggered on every Pull Request to the `main` branch:

1. **Code Quality Enforcement:** `terraform fmt -check` ensures strict formatting
2. **Configuration Validation:** `terraform validate` catches schema errors early
3. **Speculative Execution Plan:** `terraform plan` shows impending changes for review
4. **Concurrency Control:** Prevents overlapping runs that could corrupt state

### Phase 2: Continuous Deployment (Main Branch Merge)

Triggered automatically when changes are merged to `main`:

1. **Infrastructure Application:** Terraform applies infrastructure topology
2. **State Management:** S3 backend + DynamoDB locking ensures safe concurrent access
3. **Out-of-Band Secrets Retrieval:** AWS SSM Parameter Store decrypts APP_SECRET dynamically
4. **Ansible Configuration:** Dynamically generates inventory and configures compute layer
5. **CloudWatch Agent Setup:** Streams logs and metrics to centralized location
6. **End-to-End Smoke Tests:** Automated `curl` validation suite verifies service health
7. **Secure Cleanup:** Removes SSH keys and sensitive inventory from runner

---

## 🛠️ Prerequisites & Setup

### Local Prerequisites

- Terraform `>= 1.5.0`
- Ansible `>= 2.14`
- AWS CLI configured with appropriate credentials
- ACM certificate created in AWS Console (for HTTPS)

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

3. **Create ACM certificate for HTTPS:**
   ```bash
   # Go to AWS Console > ACM > Request Certificate
   # Choose domain name and validation method
   # Copy the certificate ARN for GitHub Secrets
   ```

### GitHub Secrets Setup

Set these secrets in repository settings:

| Secret | Example | Notes |
|--------|---------|-------|
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` | IAM user with EC2, RDS, SSM, CloudWatch permissions |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` | Keep secure, rotate regularly |
| `AWS_DEFAULT_REGION` | `af-south-1` | Must match S3 bucket region |
| `TF_STATE_BUCKET` | `rewards-dev-terraform-state` | S3 bucket created above |
| `ACM_CERTIFICATE_ARN` | `arn:aws:acm:af-south-1:123456789:certificate/abc123` | ACM cert ARN from AWS Console |
| `APP_SECRET` | `SuperSecureRandomString123!@#` | Min 16 chars, keep secure |
| `SSH_PRIVATE_KEY` | (private key contents) | EC2 key pair private key for Ansible SSH |
| `AWS_KEY_PAIR_NAME` | `rewards-dev-key` | EC2 key pair name in AWS |

---

## 📂 File Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yaml                 # GitHub Actions CI/CD pipeline
├── .gitignore                          # Terraform/Ansible ignore patterns
├── README.md                           # This file
├── SOLUTION.md                         # Architecture & trade-off documentation
├── ansible/
│   ├── playbook.yml                    # NGINX, UFW, CloudWatch agent config
│   ├── templates/
│   │   ├── nginx.conf.j2               # NGINX server block config
│   │   └── cloudwatch-config.json.j2   # CloudWatch agent config
│   └── hosts.ini                       # Dynamic inventory (generated by CI/CD)
└── terraform/
    ├── main.tf                         # VPC, ALB, EC2, IAM, CloudWatch, S3 backend
    ├── variables.tf                    # Input variables with validation
    ├── output.tf                       # Outputs (ALB DNS, instance ID, cleanup)
    └── .terraform.lock.hcl             # Terraform provider version lock

```

---

## 🚀 Getting Started

### Local Development (Non-Automated)

If you want to test locally before pushing to GitHub:

```bash
# 1. Navigate to Terraform directory
cd terraform

# 2. Initialize Terraform (will use S3 backend)
terraform init

# 3. Plan infrastructure changes
terraform plan -out=tfplan

# 4. Apply changes
terraform apply tfplan

# 5. Extract outputs
terraform output -json

# 6. Run Ansible playbook manually
cd ../ansible
ansible-playbook -i <EC2_PRIVATE_IP>, playbook.yml \
  -u ubuntu \
  -e "app_secret_env_var=$(aws ssm get-parameter --name /dev/rewards/APP_SECRET --with-decryption --query Parameter.Value --output text)" \
  -e "log_group_name=/aws/ec2/rewards-dev/application" \
  -e "aws_region=af-south-1" \
  --private-key ~/.ssh/rewards-dev-key.pem
```

### Automated Deployment (GitHub Actions)

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/update-web-tier
   ```

2. **Make infrastructure changes:**
   ```bash
   # Edit terraform/* files
   git add terraform/
   git commit -m "feat: update NGINX configuration"
   ```

3. **Push and create Pull Request:**
   ```bash
   git push origin feature/update-web-tier
   # Create PR on GitHub
   ```

4. **Review Terraform plan in PR** - GitHub Actions will post plan output

5. **Merge to main** - CI/CD automatically deploys to dev environment

6. **Monitor deployment** - Watch GitHub Actions logs for progress

---

## 📊 Observability & Monitoring

### CloudWatch Logs

Access centralized logs:

```bash
# View recent logs
aws logs tail /aws/ec2/rewards-dev/application --follow

# Search for errors
aws logs filter-log-events \
  --log-group-name /aws/ec2/rewards-dev/application \
  --filter-pattern "ERROR"

# Export logs to S3 for analysis
aws logs create-export-task \
  --log-group-name /aws/ec2/rewards-dev/application \
  --from $(date -d '1 day ago' +%s)000 \
  --to $(date +%s)000 \
  --destination rewards-dev-logs \
  --destination-prefix logs/
```

### CloudWatch Alarms

Three alarms monitor health:

1. **CPU High** - Triggers if CPU > 80% for 2 minutes
2. **Status Check Failed** - Triggers if EC2 fails system/instance status checks
3. **ALB Unhealthy Hosts** - Triggers if targets become unhealthy

View alarms:

```bash
aws cloudwatch describe-alarms --alarm-names \
  rewards-dev-ec2-high-cpu \
  rewards-dev-ec2-status-check \
  rewards-dev-alb-unhealthy-hosts
```

### Custom Metrics

CloudWatch agent collects:

- CPU (idle, iowait, guest time)
- Disk (usage %)
- Memory (usage %)
- Network (TCP established, time_wait)
- Processes (running, sleeping)

---

## 🧹 Cleanup Instructions

To destroy all resources and prevent AWS charges:

```bash
# 1. Destroy infrastructure via Terraform
terraform -chdir=terraform destroy -auto-approve

# 2. Delete S3 state bucket
aws s3 rm s3://rewards-dev-terraform-state --recursive
aws s3api delete-bucket --bucket rewards-dev-terraform-state --region af-south-1

# 3. Delete DynamoDB locks table
aws dynamodb delete-table --table-name terraform-locks --region af-south-1

# 4. Clean local Terraform state
rm -rf terraform/.terraform terraform/terraform.tfstate* terraform/.terraform.lock.hcl

# 5. (Optional) Delete ACM certificate
aws acm delete-certificate --certificate-arn arn:aws:acm:af-south-1:123456789:certificate/abc123
```

---

## 📈 Production Promotion Strategy

To transition this dev setup to production:

### 1. **State Isolation**
   - Create separate S3 buckets: `rewards-prod-terraform-state`
   - Create separate DynamoDB table: `terraform-locks-prod`
   - Use environment-specific workspaces or separate code paths

### 2. **Environment Variables**
   ```bash
   # environments/dev/terraform.tfvars
   aws_region = "af-south-1"
   initial_app_secret_value = var.dev_secret
   
   # environments/prod/terraform.tfvars
   aws_region = "eu-west-1"  # Different region for disaster recovery
   initial_app_secret_value = var.prod_secret
   ```

### 3. **Multi-AZ Auto Scaling**
   ```hcl
   # Replace single EC2 with ASG
   resource "aws_autoscaling_group" "prod" {
     min_size             = 3
     max_size             = 10
     desired_capacity     = 3
     vpc_zone_identifier  = [aws_subnet.private_1.id, aws_subnet.private_2.id]
     target_group_arns    = [aws_lb_target_group.web.arn]
   }
   ```

### 4. **CI/CD Approval Gates**
   ```yaml
   # .github/workflows/deploy.yaml
   - name: Manual Approval for Production
     if: github.ref == 'refs/heads/main' && github.event_name == 'push'
     uses: trstringer/manual-approval@main
     with:
       secret: ${{ github.TOKEN }}
       approvers: platform-team
   ```

### 5. **Separate Credentials**
   - Create separate AWS IAM user for prod with restricted permissions
   - Store prod secrets in separate GitHub environment
   - Use environment-specific branch protections

See `SOLUTION.md` for detailed architectural trade-offs.

---

## 🔍 Troubleshooting

### Health Check Failing

```bash
# 1. Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# 2. SSH into instance (via Systems Manager Session Manager)
aws ssm start-session --target i-1234567890abcdef0

# 3. Check NGINX status
sudo systemctl status nginx
sudo nginx -t

# 4. Check NGINX logs
sudo tail -f /var/log/nginx/error.log
```

### Ansible Playbook Fails

```bash
# Re-run manually with verbose output
cd ansible
ansible-playbook -i <IP>, playbook.yml \
  -u ubuntu \
  -e "app_secret_env_var=..." \
  --private-key ~/.ssh/key.pem \
  -vvv
```

### Terraform State Corruption

```bash
# If state is corrupted, pull from S3
aws s3 cp s3://rewards-dev-terraform-state/dev/terraform.tfstate .
terraform refresh
```

### CloudWatch Agent Not Streaming Logs

```bash
# SSH into instance and check agent status
sudo systemctl status amazon-cloudwatch-agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s

# Check agent logs
tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

---

## 📚 Additional Resources

- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Security.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [CloudWatch Logs Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html)

---

## 🤝 Contributing

1. Create feature branch: `git checkout -b feature/my-change`
2. Make changes and commit: `git commit -m "feat: describe change"`
3. Push and create PR: `git push origin feature/my-change`
4. Wait for CI/CD approval
5. Merge to `main`
6. Changes automatically deploy to dev

---

## 📄 License

This infrastructure code is provided as-is for the Rewards platform team.

---

**Last Updated:** June 4, 2026  
**Maintained By:** Cloud Infrastructure Team  
**Status:** ✅ Production-Ready (with ACM cert)
