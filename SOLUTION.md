# Engineering Solution Architecture & Trade-offs

## Architectural Choices & Rationale

1. **Compute Layer**: Implemented via a single `t3.micro` EC2 instance to balance rapid execution speed with minimal execution costs within this development footprint.
2. **Network Isolation & Zero-SSH Perimeter**: The compute instance is deployed completely within a **private subnet** with no assigned public IP. Inbound public network ingress (including port 22/SSH) is entirely eliminated. The host server accepts ingress parameters specifically restricted to traffic originating from the Application Load Balancer (ALB) Security Group proxy. This ensures direct public ingress access paths to the application layer are fully mitigated.
3. **Agentless Configuration Management**: Rather than establishing complex SSH credential infrastructure or deploying legacy configuration management tools, server orchestration is handled natively via **AWS Systems Manager (SSM) RunShellScript**. By utilizing an IAM instance profile (`AmazonSSMManagedInstanceCore`) and private VPC interface endpoints, the GitHub Actions runner safely executes remote shell payloads out-of-band without exposing public management ports.
4. **Configuration / Runtime Engine**: NGINX was used instead of a custom application binary layer. This fulfills production requirements cleanly out of the box, handles reverse-proxying natively, auto-restarts cleanly through systemd process managers, and decouples static infrastructure provisioning from pure raw compute configuration tasks.
5. **Observability Strategy**: Basic metrics and target cloud alarms are implemented natively inside AWS CloudWatch. This provides deep diagnostic coverage tracking machine stress boundaries (`CPUUtilization`) and keeps operational steps minimal while alerting operations to active performance degradation.

---

## State Management Trade-offs

For immediate development and testing constraints, local state execution parameters are initialized inside the ephemeral GitHub Actions execution runner sandbox. 

* **Trade-off Evaluation**: While optimal for rapid prototype lifecycles and zero-infrastructure overhead, this model creates state volatility. Team scalability requires an immediate migration to a remote state pattern using an AWS S3 backend block combined with distributed tracking state locks controlled via Amazon DynamoDB tables to prevent state corruption, data loss, or simultaneous provisioning conflicts.

---

## Production Promotion Strategy & Environmental Segmentation

To systematically promote alterations securely into an isolated production runtime framework, the design paths can scale horizontally through:

1. **State Isolation**: Structuring dedicated backend workspace configurations or physically separated infrastructure directories to strictly segment environment states (e.g., matching structures using `environments/dev/` and `environments/prod/`).
2. **Scale Paths & High Availability**: Transitioning from a single active EC2 instance entity configuration to a highly resilient infrastructure tier utilizing AWS Auto Scaling Groups (ASG). This ensures the architecture automatically stretches fluidly across multiple distinct Availability Zones (multi-AZ layout) tied securely beneath the existing ALB layer to handle erratic production traffic surges.
3. **Strict Outbound Network Perimeters**: While the development environment utilizes VPC Endpoints to connect to AWS SSM endpoints without the financial overhead of a NAT Gateway, a production lifecycle should introduce highly available NAT Gateways or AWS Network Firewalls in the public tier to allow controlled, secure outbound internet traffic for package repository mirrors (`apt update`) and third-party API dependencies.
4. **CI/CD Guardrails & Multi-Party Approvals**: Extending the execution pipelines with structural multi-stage control gates. Pull Requests targeted at stable production branches will enforce automated integration testing suites, strict static application security testing (SAST), and mandatory manual sign-offs before executing modifications against live Production workloads.
