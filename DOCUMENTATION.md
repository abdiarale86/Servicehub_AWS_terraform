# Designing and Deploying a Secure, Scalable Enterprise Platform with Infrastructure as Code

## 📌 Current Situation / Challenge

ServiceHub started as a service management platform intended for internal use. The requirement wasn't just "get it running on AWS" — it needed to hit specific, measurable targets:

- High availability (~99.9% uptime)
- Defense-in-depth security, not a single perimeter check
- Auto-scaling to absorb traffic spikes without manual intervention
- A dev environment that stays under budget (~£70/month)

Even though Kubernetes and fully cloud-native platforms get most of the attention, a traditional three-tier architecture — load balancer, compute, database — still covers the vast majority of real-world enterprise workloads, and it's simpler to reason about, secure, and operate.

## 🎯 Goal

Design and deploy a production-grade three-tier platform entirely through Terraform, with:

- A public-facing Application Load Balancer as the only internet-exposed component
- Application servers and databases fully isolated in private subnets
- Auto Scaling so the platform can grow and self-heal without manual EC2 management
- Least-privilege IAM roles instead of access keys
- A remote, locked, encrypted Terraform state backend from day one

## 🧠 What I Will Learn

Through this project, I aimed to strengthen my skills in:

- Designing a multi-AZ VPC with clear public/private/database subnet tiers
- Building reusable Terraform modules instead of one monolithic configuration
- Chaining module outputs into other modules' inputs (network → security → compute)
- Configuring an Auto Scaling Group behind an ALB with health-check-based routing
- Bootstrapping EC2 instances automatically with `user_data` instead of manual configuration
- Setting up a secure, team-safe S3 + DynamoDB backend for Terraform state

## 🛠️ Project Tasks

**1. Design the Network**
- Plan a `/16` VPC with distinct public, private-app, and private-db subnet tiers across two AZs
- Decide routing per tier (who gets internet access, and how)

**2. Build the Security Model**
- Chain security groups so each tier only accepts traffic from the tier above it
- Replace access keys with IAM instance roles scoped to exactly what the app needs

**3. Build the Terraform Modules**
- One module per concern: `vpc`, `security-groups`, `iam`, `s3`, `alb`, `rds`, `elasticache`, `ec2`
- Wire modules together through outputs/inputs in the `dev` environment

**4. Automate Instance Bootstrap**
- Use `user_data` to install dependencies, configure the app, and start it as a systemd service on first boot

**5. Deploy and Verify**
- `terraform init` / `plan` / `apply`
- Confirm the ALB routes to healthy targets and the health endpoints respond correctly

**Flow:**

```
Terraform (modules/vpc, security-groups, iam, s3, alb, rds, elasticache, ec2)
        │
        ▼
VPC (2 AZs) → Public Subnets / Private-App Subnets / Private-DB Subnets
        │
        ▼
Security Group Chain: Internet → ALB → EC2 → RDS / Redis
        │
        ▼
Auto Scaling Group (EC2, user_data bootstrap) ← Target Group ← ALB
        │
        ▼
RDS PostgreSQL (Multi-AZ capable) + ElastiCache Redis (Private-DB Subnets)
```

## Why This Project Matters

A lot of teams reach straight for the most fashionable stack without asking whether it fits the actual requirement. A well-designed traditional three-tier setup — done properly, with real network isolation and least privilege — is often the more maintainable choice, and it's exactly the kind of infrastructure most enterprises are still running today.

## Final Outcome

By the end of this project:

- A fully modular Terraform codebase, deployable to dev/staging/prod by changing variables
- A network with zero direct internet access to the app or database tiers
- An Auto Scaling Group that bootstraps identical, ready-to-serve instances with no manual steps
- A remote state backend that's versioned, encrypted, and lock-protected

---

## 1. Designing the Network

Rather than starting with resources, I started with a CIDR plan. A `/16` VPC (`10.0.0.0/16`) gives far more address space than is needed today, but it means the network never has to be redesigned as it grows.

Each tier gets its own subnet range, spread across two Availability Zones (`eu-west-2a` / `eu-west-2b`) for resilience:

| Tier | CIDR blocks | Purpose |
|------|-------------|---------|
| **Public** | `10.0.1.0/24`, `10.0.2.0/24` | ALB, NAT Gateways |
| **Private-App** | `10.0.11.0/24`, `10.0.12.0/24` | EC2 application instances |
| **Private-DB** | `10.0.21.0/24`, `10.0.22.0/24` | RDS, ElastiCache |

The numbering pattern (`1.x` public, `11.x` app, `21.x` database) makes the tier obvious from the CIDR alone, which helps a lot when debugging routing or reading logs later.

**Routing per tier**, defined in `modules/vpc/main.tf`:

```hcl
# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Private Route Tables (one per AZ for NAT Gateway)
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[count.index].id
    }
  }
}
```

- **Public subnets** route `0.0.0.0/0` straight to the Internet Gateway — full inbound/outbound.
- **Private-app subnets** route outbound-only traffic through a NAT Gateway — no direct inbound path from the internet.
- **Private-db subnets** get no default route at all — there's no way out to the internet, by design.

One NAT Gateway is deployed **per Availability Zone** rather than a single shared one:

```hcl
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? length(var.availability_zones) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
}
```

A single NAT Gateway would be cheaper, but it becomes a single point of failure for every private-app instance's outbound connectivity. Two NAT Gateways cost roughly double, but mean an AZ outage doesn't take down the other AZ's outbound traffic.

VPC Flow Logs are enabled by default (`enable_flow_logs = true`), shipping all traffic metadata to a dedicated CloudWatch Log Group for later security review — network isolation is only useful if you can also see what's crossing it.

## 2. Security: Defense in Depth

Instead of relying on one perimeter control, each tier's security group only trusts the specific security group above it — not an IP range, not "the VPC," just the exact resource that's supposed to talk to it.

**The chain, from `modules/security-groups/main.tf`:**

```
Internet → ALB (Port 80/443)
              ↓
           EC2 (Port 5000) ← Only from ALB's security group
              ↓
           RDS (Port 5432)  ← Only from EC2's security group
           Redis (Port 6379) ← Only from EC2's security group
```

```hcl
# EC2 only accepts app traffic from the ALB — nothing else
resource "aws_security_group" "ec2" {
  ingress {
    description     = "HTTP from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    description = "SSH from VPC (for management)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

# RDS only accepts Postgres traffic from EC2 — no CIDR ranges at all
resource "aws_security_group" "rds" {
  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
}
```

Referencing a security group instead of a CIDR block matters: even if an EC2 instance were compromised, an attacker sitting on it can only reach what that instance's security group is explicitly allowed to reach — the RDS and Redis security groups don't know or care what IP the traffic came from, only which security group it's attached to.

**IAM roles instead of access keys**, from `modules/iam/main.tf`:

```hcl
resource "aws_iam_role_policy" "s3_access" {
  name = "s3-access-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}
```

The EC2 instance role is scoped to exactly one S3 bucket, plus narrowly-scoped Secrets Manager and SSM Parameter Store access under a `project_name/environment/*` path — no wildcard resources, no credentials to leak, no keys sitting in a config file. If the instance were ever compromised, the blast radius stops at that one bucket and that one parameter path.

Launch templates also enforce **IMDSv2** (`http_tokens = "required"`), closing off the SSRF-to-credential-theft path that IMDSv1 is vulnerable to, and EBS volumes are encrypted at rest by default.

## 3. Building the Terraform Modules

Instead of one large configuration, the infrastructure is split into eight modules, each owning one concern:

```
Servicehub_AWS_terraform/
└── terraform/
    ├── modules/
    │   ├── vpc/              # VPC, subnets, routing, NAT, flow logs
    │   ├── security-groups/  # ALB / EC2 / RDS / Redis security groups
    │   ├── iam/               # EC2 instance role + scoped policies
    │   ├── s3/                # Attachments bucket
    │   ├── alb/                # Load balancer, target group, health check
    │   ├── rds/                # PostgreSQL, subnet group, parameter group
    │   ├── elasticache/         # Redis cluster
    │   └── ec2/                  # Launch template + Auto Scaling Group
    └── environments/
        └── dev/
            ├── main.tf             # Wires every module together
            ├── variables.tf
            ├── outputs.tf
            ├── backend.tf           # S3 + DynamoDB remote state
            ├── terraform.tfvars
            ├── user_data.sh          # EC2 bootstrap script
            ├── setup-backend.sh       # Creates the S3/DynamoDB backend
            └── cleanup.sh              # Tears down resources outside Terraform's reach
```

The `dev/main.tf` environment file is the orchestrator — it doesn't define a single AWS resource directly, it just calls each module and threads outputs from one into the inputs of the next:

```hcl
module "vpc" {
  source = "../../modules/vpc"
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.availability_zones
  public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
  private_app_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  private_db_subnet_cidrs  = ["10.0.21.0/24", "10.0.22.0/24"]
  enable_nat_gateway = true
  enable_flow_logs   = true
}

module "security_groups" {
  source = "../../modules/security-groups"
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr
}

module "ec2" {
  source = "../../modules/ec2"
  subnet_ids           = module.vpc.private_app_subnet_ids
  security_group_ids   = [module.security_groups.ec2_sg_id]
  iam_instance_profile = module.iam.instance_profile_name
  target_group_arns    = [module.alb.target_group_arn]

  user_data = templatefile("${path.module}/user_data.sh", {
    db_endpoint    = module.rds.db_endpoint
    db_name        = module.rds.db_name
    db_password    = var.db_password
    redis_endpoint = module.elasticache.redis_endpoint
    s3_bucket      = module.s3.bucket_name
    aws_region     = var.aws_region
    environment    = var.environment
  })
}
```

The `ec2` module is the clearest example of everything coming together — it pulls its subnets and security group from `vpc` and `security_groups`, its IAM profile from `iam`, its target group from `alb`, and its runtime configuration (DB endpoint, Redis endpoint, S3 bucket name) from `rds`, `elasticache`, and `s3`. Terraform resolves the dependency graph automatically from these references, so module order in the file doesn't matter — the data flow does.

**The ALB's health check**, tying the load balancer to the application:

```hcl
module "alb" {
  source = "../../modules/alb"
  health_check = {
    path                = "/health/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
```

**The Auto Scaling Group**, from `modules/ec2/main.tf`, uses a rolling instance refresh so template changes replace instances gradually instead of all at once:

```hcl
resource "aws_autoscaling_group" "main" {
  health_check_type = "ELB"
  health_check_grace_period = 300

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  termination_policies = ["OldestInstance"]
}
```

`health_check_type = "ELB"` means the ASG trusts the ALB's health check, not just whether the EC2 instance is "running" — an instance that's up but failing `/health/health` gets cycled out automatically.

## 4. Automating Instance Bootstrap with `user_data`

The biggest lever for eliminating configuration drift is `user_data.sh` — a script that runs once on first boot and turns a bare Amazon Linux instance into a fully configured, running application node, with no manual steps.

```bash
# Install dependencies
yum install -y python3.11 python3.11-pip git postgresql15 redis6 amazon-cloudwatch-agent

# Wire up runtime config from Terraform outputs
cat > /etc/environment << ENVEOF
DATABASE_URL=postgresql://servicehub_admin:${db_password}@${db_endpoint}/${db_name}
REDIS_URL=redis://${redis_endpoint}:6379/0
S3_BUCKET=${s3_bucket}
AWS_REGION=${aws_region}
ENVEOF

# Run the app under systemd, not a bare process
cat > /etc/systemd/system/servicehub.service << 'SVCEOF'
[Service]
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 120 app:app
Restart=always
RestartSec=3
SVCEOF

systemctl enable servicehub
systemctl start servicehub
```

The Flask app it deploys exposes exactly the endpoints the rest of the stack depends on:

- `/health/health` — the ALB's target-group health check
- `/health/ready` — dependency checks (DB, Redis)
- `/health/live` — liveness probe
- `/metrics` — Prometheus-format metrics

Because `db_endpoint`, `redis_endpoint`, and `s3_bucket` are passed in via `templatefile()` from the actual Terraform module outputs (not hardcoded), every instance the Auto Scaling Group launches — whether it's the first one or the tenth one after a scale-out event — comes up already pointed at the right database, cache, and bucket. There's no post-boot configuration step and no drift between instances.

## 5. Remote State: S3 + DynamoDB Backend

Before any real infrastructure gets created, the Terraform state itself needs a safe home. `setup-backend.sh` automates that:

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
TABLE_NAME="${PROJECT_NAME}-terraform-locks"

aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"

aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
```

Naming the bucket with the AWS account ID guarantees global uniqueness without any manual coordination. `set -e` at the top means the script stops the moment any step fails, instead of limping forward with a half-configured backend. Every step is also idempotent — checking whether the bucket or table already exists before trying to create it — so the script is safe to re-run.

This gives the project:

- **Versioning** — every state change is recoverable, not just the latest one
- **Encryption at rest** — the state file can contain sensitive values (endpoints, ARNs) and shouldn't sit in plaintext
- **Blocked public access** — a locked-down bucket by default, not an opt-in
- **DynamoDB locking** — prevents two `terraform apply` runs from racing each other and corrupting state

`backend.tf` then just points at what the script created:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-project-a-terraform-state-490004651290"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-project-a-terraform-locks"
    encrypt        = true
  }
}
```

Sensitive input — the database password — is deliberately kept out of `terraform.tfvars` and out of version control entirely, passed in at apply-time via an environment variable instead:

```bash
export TF_VAR_db_password='Password123!'
```

## 6. Deployment

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

`init` downloads providers and connects to the S3/DynamoDB backend created in the previous step. `plan` shows exactly what's about to be created — for this stack, that's roughly 30+ resources: a VPC with 6 subnets across 2 AZs, 2 NAT Gateways, 4 security groups, an ALB, an Auto Scaling Group, an RDS instance, a Redis cluster, an S3 bucket, and the IAM roles tying it together. `apply` then provisions everything in dependency order — RDS is typically the longest step at 8-10 minutes, with the rest of the stack finishing in a couple of minutes.

## 7. Verification

Once `apply` finishes, the ALB's DNS name is the platform's public entry point:

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
curl http://${ALB_DNS}/health/health
# {"status":"healthy","timestamp":1705328914.123}
```

**Checks that confirm the deployment actually worked, end to end:**

- **Target group health** (EC2 → Target Groups → Targets) — should show the instance as `healthy`, not just `running`. This is the single most useful signal: an instance can be up in EC2's view while still failing the app-level health check.
- **RDS status** — `Available`, in the correct DB subnet group, reachable only from the EC2 security group.
- **ElastiCache status** — `Available`, same subnet/security group pattern as RDS.
- **CloudWatch Logs** — the first place to look if `user_data` failed partway through, or the app never came up.

## 📚 Key Lessons Learned

**1. Design the network before writing a single resource**
Deciding the CIDR plan and routing strategy up front made every subsequent module (security groups, ALB, RDS) a matter of referencing existing outputs rather than guessing at network boundaries.

**2. Security groups referencing security groups beats CIDR ranges**
Chaining `security_groups = [aws_security_group.alb.id]` instead of allowing a CIDR block means access is tied to *what* a resource is, not *where* it happens to sit on the network.

**3. `user_data` removes an entire class of bugs**
Every instance the Auto Scaling Group launches is provisioned identically. There's no "it worked on the first instance but not the third" — because there's no manual step where that kind of drift could creep in.

**4. Remote state isn't optional, even for solo projects**
Locking (via DynamoDB) and versioning (via S3) protect against the exact failure mode that's easy to dismiss until it happens: two applies racing, or a bad apply with no way to see the previous state.

**5. Two NAT Gateways is a deliberate cost/resilience tradeoff, not a default**
It roughly doubles NAT cost to remove a single point of failure for outbound connectivity. Worth knowing you can drop to one for a lower-stakes dev environment, and why you wouldn't for anything closer to production.

## 📊 Results After Implementation

- Availability: Multi-AZ VPC, ALB health-check-based routing, self-healing Auto Scaling Group
- Security: zero direct internet access to app or database tiers, IAM roles instead of access keys, encrypted storage and IMDSv2 enforced
- Deployment time: full stack (~30 resources) provisioned in ~10-15 minutes, versus hours of manual console work
- Configuration drift: zero — every instance is bootstrapped identically via `user_data`
- Dev environment cost: within the ~£70/month target

## Final Thoughts

The interesting part of this project wasn't any single AWS service — it was the sequencing: get the network boundaries right first, let security groups enforce those boundaries instead of application code, and automate everything downstream of that so scaling and recovery don't depend on a human doing the right manual step at 2am.

Kubernetes and fully serverless designs solve real problems, but a well-isolated three-tier VPC with Auto Scaling, chained security groups, and IAM-based least privilege still covers most of what "secure and scalable" actually requires — and it's a lot easier to reason about when something goes wrong.

## Skills Demonstrated

- Multi-AZ VPC design (public/private-app/private-db tiers, NAT Gateway strategy, VPC Flow Logs)
- Terraform module design and cross-module output chaining
- Security group chaining for defense-in-depth network access control
- Least-privilege IAM roles and instance profiles (no static access keys)
- Auto Scaling Group configuration with ALB health-check integration and rolling instance refresh
- EC2 bootstrap automation via `user_data` and `templatefile()`
- Remote Terraform state management (S3 + DynamoDB) with encryption, versioning, and locking
- RDS PostgreSQL and ElastiCache Redis provisioned into isolated private subnets

## Reference

Full narrative write-up: [Designing and Deploying a Secure, Scalable Enterprise Platform with Infrastructure as Code: PART-1](https://medium.com/@a.arale86)

Code repository: [abdiarale86/Servicehub_AWS_terraform](https://github.com/abdiarale86/Servicehub_AWS_terraform)
