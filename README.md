# ServiceHub: Secure, Scalable Infrastructure with Terraform
<img width="700" height="574" alt="image" src="https://github.com/user-attachments/assets/7d5166de-f2ef-48a9-9668-0ba9168603c1" />

> **A production-grade three-tier AWS platform — Multi-AZ networking, chained security groups, IAM-based least privilege, and self-healing Auto Scaling, all defined as code**

[![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EC2%20%7C%20RDS%20%7C%20ALB-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/Redis-DC382D?style=for-the-badge&logo=redis&logoColor=white)](https://redis.io/)

## 📋 Project Overview

ServiceHub is a service management platform built to hit specific production targets — ~99.9% uptime, defense-in-depth security, auto-scaling under load, and a dev environment under £70/month — using a traditional three-tier architecture instead of a fully cloud-native rebuild. Every layer (network, security, compute, database, cache) is defined as reusable Terraform modules and wired together in a single environment configuration.

**🚨 📖 [View Full Documentation](DOCUMENTATION.md)** for the detailed step-by-step build. 🚨

🚨 The full narrative write-up is also on Medium: [Designing and Deploying a Secure, Scalable Enterprise Platform with Infrastructure as Code: PART-1](https://medium.com/@a.arale86) 🚨

## 🏗️ Architecture

```
Internet
   │
   ▼
Application Load Balancer (Public Subnets, 2 AZs)
   │  ← security group: only ALB accepts 80/443 from the internet
   ▼
Auto Scaling Group / EC2 (Private-App Subnets, 2 AZs)
   │  ← security group: only accepts 5000 from the ALB's SG
   ▼
RDS PostgreSQL (Multi-AZ capable)      ElastiCache Redis
(Private-DB Subnets)                   (Private-DB Subnets)
   ← both only accept traffic from the EC2 security group
```

**Workflow:** Internet → ALB (public subnets) → Auto Scaling Group of EC2 instances (private-app subnets, bootstrapped via `user_data`) → RDS PostgreSQL + ElastiCache Redis (private-db subnets, no internet route at all).

## 🚀 Key Features

- **Multi-AZ Network Design** - `/16` VPC split into public, private-app, and private-db tiers across two Availability Zones
- **Security Group Chaining** - each tier only trusts the specific security group above it (ALB → EC2 → RDS/Redis), never a raw CIDR range
- **Least-Privilege IAM** - EC2 instance role scoped to one S3 bucket and a narrow Secrets Manager/SSM path, no static access keys
- **Self-Healing Auto Scaling** - ALB health-check-driven ASG with rolling instance refresh and `OldestInstance` termination policy
- **Zero-Touch Bootstrap** - `user_data` installs, configures, and starts the app as a systemd service on first boot — no manual server setup
- **Encrypted, Locked Remote State** - S3 backend with versioning + encryption, DynamoDB table for state locking
- **IMDSv2 Enforced** - launch template requires session tokens, closing the SSRF-to-credential-theft path

## 🛠️ Technologies

| Category | Technologies |
|----------|-------------|
| **Networking** | VPC, public/private subnets (2 AZs), NAT Gateways, VPC Flow Logs |
| **Compute** | EC2, Launch Templates, Auto Scaling Groups, Application Load Balancer |
| **Database / Cache** | RDS PostgreSQL 15, ElastiCache Redis |
| **Security** | IAM roles/instance profiles, chained security groups, IMDSv2, encrypted EBS/RDS/S3 |
| **IaC** | Terraform, reusable modules, `templatefile()`, remote S3 + DynamoDB backend |
| **App Runtime** | Python 3.11, Flask, Gunicorn, systemd |

## 💡 What I Learned

✅ Designing a multi-AZ VPC with clear public/private-app/private-db tiers and per-tier routing
✅ Building reusable Terraform modules and chaining outputs across them (network → security → compute)
✅ Configuring an Auto Scaling Group behind an ALB with health-check-based routing and rolling refresh
✅ Bootstrapping EC2 instances automatically with `user_data` instead of manual configuration
✅ Setting up a secure, team-safe S3 + DynamoDB backend for Terraform state
✅ Scoping IAM roles to exactly what an application needs, instead of broad managed policies

## 📁 Project Structure

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

## 🔧 Key Implementation Highlights

### Security Group Chain
- ALB accepts 80/443 from the internet — the only internet-facing component
- EC2 accepts port 5000 only from the ALB's security group
- RDS (5432) and Redis (6379) accept traffic only from the EC2 security group — no CIDR ranges anywhere in the chain

### Auto Scaling + Bootstrap
- Launch template enforces IMDSv2 and encrypted EBS volumes
- `user_data.sh` installs dependencies, writes runtime config from actual Terraform outputs (DB endpoint, Redis endpoint, S3 bucket), and starts the app under systemd with `Restart=always`
- ASG uses `health_check_type = "ELB"`, so an instance that's running but failing `/health/health` gets cycled out automatically

### Challenges Overcome
- ✅ Avoided a single NAT Gateway as a shared point of failure by deploying one per AZ
- ✅ Kept the database tier fully private — private-db subnets have no default route to the internet at all
- ✅ Made the Terraform backend setup idempotent and account-ID-scoped so it's safe to re-run and globally unique

## 📚 Documentation

For the complete walkthrough including:
- The CIDR/subnet design and routing strategy per tier
- Full Terraform code for every module
- The `user_data` bootstrap script and health-check wiring
- Deployment, verification, and lessons learned

**➡️ [Read the Full Documentation](DOCUMENTATION.md)**

## 🤝 Connect With Me

<div align="center">

[![Email](https://img.shields.io/badge/Email-abdijarale%40gmail.com-D14836?style=for-the-badge&logo=gmail&logoColor=white)](mailto:abdijarale@gmail.com)
[![GitHub](https://img.shields.io/badge/GitHub-abdiarale86-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/abdiarale86)

</div>

---

<div align="center">

**⭐ If you found this project helpful, please consider giving it a star!**

</div>
