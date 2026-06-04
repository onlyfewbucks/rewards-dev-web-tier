# Engineering Solution Architecture & Trade-offs

## Architectural Choices & Rationale
1. **Compute Layer**: Implemented via a single `t3.micro` EC2 instance to balance extreme speed of execution with minimal execution costs within this single environment demonstration scope.
2. **Network Isolation Model**: The host server accepts ingress parameters specifically restricted to the Application Load Balancer Security Group. This ensures that direct public ingress access paths to the application layer are fully mitigated without paying provisioning fees for a NAT Gateway topology.
3. **Configuration / Runtime Engine**: NGINX was used instead of a custom node/python binary layer. This fulfills production requirements cleanly out of the box, auto-restarts cleanly through systemd process managers, and cleanly decouples infrastructure definitions from pure raw compute delivery tasks.
4. **Observability Strategy**: Basic metrics and target cloud alarms were implemented directly inside the cloud provider layer. This provides deep diagnostic coverage tracking machine stress boundaries (`CPUUtilization`) and keeps operational steps minimal.

## State Management Trade-offs
For the immediate development constraints, local state execution parameters are initialized inside the GitHub automation execution runner sandbox. 

* **Trade-off Evaluation**: While optimal for single-day rapid prototype lifecycles, team scalability requires migration to an active remote state pattern using AWS S3 blocks alongside distributed tracking state locks controlled via Amazon DynamoDB tables to prevent resource contention or simultaneous provisioning conflicts.

## Production Promotion Strategy & Environmental Segmentation
To systematically promote alterations securely into an isolated production runtime framework, the design paths can scale horizontally through:

1. **State Isolation**: Structuring dedicated workspace configurations or physical code paths tracking environmental state mappings (e.g., matching structures using `environments/dev/` and `environments/prod/`).
2. **Scale Paths**: Transitioning from a single active EC2 instance entity configuration to a scalable infrastructure tier utilizing AWS Auto Scaling Groups (ASG). This ensures the architecture stretches fluidly across multiple distinct Availability Zones (multi-AZ layout) tied securely beneath the existing ALB layer.
3. **CI/CD Guardrails**: Extending the execution pipelines with structural multi-stage control gates. Pull Requests targeted at stable production branches will enforce conditional validation checks combined with structural pipeline approvals before executing modifications against live Production workloads.
