# AWS Infrastructure — Terraform Demo
###  DevOps Take-Home Assignment

---

## Prerequisites

| Requirement | Version |
|---|---|
| Terraform | >= 1.5.0 |
| AWS CLI | >= 2.x, configured with credentials |
| AWS Account | Permissions for ECS, RDS, SQS, VPC, IAM, S3, CloudWatch |

---

## Project Structure

```
terraform/
├── main.tf                      # Root module — wires all modules together
├── variables.tf                 # Input variables
├── outputs.tf                   # Stack outputs
├── versions.tf                  # Provider and backend config
├── terraform.tfvars.example     # Example variable values
└── modules/
    ├── networking/              # VPC, subnets, NAT Gateway, Elastic IP, security groups
    ├── iam/                     # ECS execution role, API task role, worker task role
    ├── sqs/                     # Task queue + dead-letter queue
    ├── alb/                     # Application Load Balancer, target group, listener
    ├── rds/                     # PostgreSQL primary + read replica
    ├── s3/                      # Application storage bucket
    ├── ecs/                     # ECS cluster, API + worker Fargate services, autoscaling
    └── monitoring/              # CloudWatch alarms, SNS topic, ops dashboard
```

---

## Setup

```bash
# 1. Copy the example vars file
cp terraform.tfvars.example terraform.tfvars

# 2. Fill in required values
vim terraform.tfvars
```

Minimum required values:

```hcl
aws_region  = "ap-southeast-2"
db_password = "your-secure-password"
alert_email = "your-email@example.com"
```

---

## Deployment

```bash
# Initialise providers and modules - validated
terraform init 

# Validate all configuration
terraform validate - validated

# Preview what will be created - validated
terraform plan -var-file="terraform.tfvars"

# Apply — full stack provisioning  
terraform apply -var-file="terraform.tfvars"
```

---

## Key Outputs

After apply, retrieve key values:

```bash
# All outputs
terraform output

# Fixed outbound IP — share with partners for whitelisting
terraform output nat_gateway_elastic_ip

# ALB DNS — entry point for API traffic
terraform output alb_dns_name

# SQS queue URL
terraform output sqs_queue_url

# RDS endpoints (sensitive — use -raw flag)
terraform output -raw db_endpoint
terraform output -raw db_replica_endpoint
```

---

## Inspect

```bash
# Check ECS services are running
aws ecs list-services \
  --cluster staging-cluster \
  --region ap-southeast-2

# Check SQS queue depth
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw sqs_queue_url) \
  --attribute-names ApproximateNumberOfMessages

# Check RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier staging-postgres-primary \
  --query 'DBInstances[0].DBInstanceStatus'

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix staging \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table
```

---

## Autoscaling

| Service | Metric | Policy | Min | Max |
|---|---|---|---|---|
| API | CPU Utilisation | Target tracking at 60% | 2 | 10 |
| Worker | SQS Queue Depth | Step scaling — +1 at 100 msgs, +3 at 500, +5 at 2000 | 1 | 20 |

---

## Destroy

```bash
terraform destroy -var-file="terraform.tfvars"
```

> **Note:** If destroy fails on RDS, set `deletion_protection = false` in `modules/rds/main.tf`, run `terraform apply`, then retry destroy.

---

## Shortcuts & Assumptions

| Shortcut | Production Approach |
|---|---|
| `nginx:latest` placeholder image | Replace with real ECR image URI |
| HTTP on ALB (port 80) | HTTPS with ACM certificate on port 443 |
| DB password in `terraform.tfvars` | AWS Secrets Manager with automatic rotation |
| `deletion_protection = false` | Set `true` in production |
| `skip_final_snapshot = true` | Set `false` in production |
| Local Terraform state | S3 backend + DynamoDB lock — config ready in `versions.tf` |
| Single AZ RDS | Enable Multi-AZ when SLAs require sub-minute RTO |
| SSM for DB password | Secrets Manager in production |


##AI Usage Disclosure

What I Designed & Decided Myself

The full architecture — ECS Fargate, SQS async pattern, RDS read replicas, NAT Gateway fixed IP, phased migration approach
All technology trade-offs — ECS vs EKS, RDS vs Aurora, SQS vs ElastiCache, Multi-AZ deferral
The 3-phase migration plan and prioritization framework
Autoscaling thresholds, security group rules, and IAM policy scopes
Database scalability strategy — async offload, bulk S3 ingest, read replica routing

Verification
All Terraform code was validated using terraform init, terraform validate, and terraform plan. Architectural decisions, trade-offs, and design rationale can be explained and defended in full without AI assistance.

Tools Used

Claude (Anthropic) via claude.ai — used selectively to accelerate drafting and boilerplate generation

What AI Assisted With

Generating Terraform boilerplate and module structure based on architecture decisions already made.
Drafting and formatting document sections based on design decisions I defined.
Producing diagram draw.io based on the architecture I designed.
Proofreading and refining written content for clarity and tone.


**For Terraform**

I designed the module structure, resource relationships, and architecture decisions independently based on my Terraform knowledge and AWS experience. I used Claude to accelerate the scripting of the boilerplate HCL — translating my architecture decisions into working code faster than writing from scratch. I reviewed every module in detail, identified and corrected syntax errors during terraform validate, and validated that the resource configurations, IAM policies, security group rules, and autoscaling policies correctly reflect the intended architecture. The Terraform code represents my design — AI was used as a scripting accelerator, not a decision-maker.

Prompt - 

"Generate a complete modular Terraform 1.x configuration for the given architecture. Create separate modules for networking, IAM, SQS, ALB, RDS, S3, ECS, and monitoring. Each module should have its own main.tf, variables.tf, and outputs.tf. The ECS module should include two Fargate services — one for the Python API scaling on CPU and one for Celery workers scaling on SQS queue depth using step scaling. Include CloudWatch alarms for key metrics and an SNS topic for alerting."

**Architecture draw.io**

I designed the full architecture layout — defining all layers, components, traffic flows, and groupings — and provided the following prompt to generate the draw.io XML:
 
Prompt

"Generate a draw.io XML diagram for the following AWS target architecture with 6 layers: Internet layer with Users, Partner Systems, and GitHub; Public Subnet with CloudFront, Internet Gateway, ALB, and NAT Gateway with Elastic IP callout; Private Compute Subnet with ECS Cluster containing API and Worker Fargate services, SQS Queue with DLQ, and S3 Bulk Staging bucket; Data Layer with RDS Proxy, RDS Primary, Read Replica, Secrets Manager, and ECR; Observability layer with CloudWatch, Prometheus, Grafana, and Kibana; CI/CD layer with GitHub Actions and Terraform. Use colour-coded connections to distinguish user traffic, database connections, async queue flow, replication, and IaC provisioning. Include a legend."

After generation I reviewed the diagram to confirm all components, connections, and layer groupings accurately reflected the architecture design document.


**Cloud Cost Approx table chart**

Prompt - 
"Summarize the following cost optimization decisions in a concise, professional way for an architecture document. Focus on the strategic trade-offs and percentage-level savings rather than exact dollar amounts. Emphasize how these decisions are startup-friendly, reduce operational overhead, and can be revisited as the company scales.

Highlight concepts such as:

	Reducing infrastructure redundancy early to save operational cost
	Choosing managed services to lower operational burden even if compute cost is slightly higher
	Limiting replicas to cut replication cost roughly in half
	Selecting cost-efficient messaging services for asynchronous workloads
	Avoiding expensive SaaS monitoring tools until team scale justifies them
	Using spot capacity to significantly reduce stateless worker compute costs
	The tone should reflect intentional cost-awareness, phased optimization, and readiness to scale when business or SLA requirements increase."

**Monitoring Thresholds**

Approximate threshold values for CloudWatch alarms were informed by industry-standard baselines and validated against AWS documentation. The following prompt was used to sense-check the values:

"For an ECS Fargate application with SQS-based worker autoscaling and RDS PostgreSQL, suggest reasonable starting CloudWatch alarm thresholds for API CPU, worker CPU, SQS queue depth, oldest message age, RDS connections, RDS free storage, and ALB 5xx error rate."

The suggested values can be reviewed and adjusted based on the specific instance sizes and capacity limits in this architecture.
