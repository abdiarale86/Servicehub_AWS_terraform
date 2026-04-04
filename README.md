# ServiceHub Infrastructure - Phase 1: Reusable Terraform Modules

## Overview
Production-grade, modular Terraform infrastructure for deploying ServiceHub on AWS. This infrastructure demonstrates enterprise best practices including:

- **Modular Design**: Reusable modules for each component
- **Multi-Environment Support**: Dev, Staging, Production with workspace isolation
- **Security Best Practices**: Least privilege, encryption, private subnets
- **High Availability**: Multi-AZ deployment for RDS and ALB
- **Scalability**: Auto Scaling Groups for EC2 instances
- **Compliance**: Tagging strategy, audit logging, encryption

## Architecture

```
Internet → Route 53 → ALB (Public Subnets)
                       ↓
                  EC2 Instances (Private Subnets)
                       ↓
                  RDS PostgreSQL (Private Subnets - Multi-AZ)
                       ↓
                  ElastiCache Redis (Private Subnets)
                       ↓
                  S3 Bucket (Attachments)
```

## Module Structure

```
terraform/
├── modules/
│   ├── vpc/                  # Custom VPC with public/private subnets
│   ├── security-groups/      # Security groups for each tier
│   ├── alb/                  # Application Load Balancer
│   ├── ec2/                  # Launch templates and instances
│   ├── rds/                  # PostgreSQL database
│   ├── elasticache/          # Redis cache
│   ├── s3/                   # S3 bucket for attachments
│   └── iam/                  # IAM roles and policies
├── environments/
│   ├── dev/                  # Development environment
│   ├── staging/              # Staging environment
│   └── prod/                 # Production environment
└── backend.tf                # Remote state configuration
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- S3 bucket for remote state (create manually first)
- DynamoDB table for state locking (create manually first)

## Quick Start

### 1. Create Backend Resources

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://servicehub-terraform-state-<your-account-id> --region eu-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket servicehub-terraform-state-<your-account-id> \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name servicehub-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-2
```

### 2. Deploy Development Environment

```bash
cd environments/dev
terraform init
terraform workspace new dev
terraform plan
terraform apply
```

### 3. Deploy Staging Environment

```bash
cd environments/staging
terraform init
terraform workspace new staging
terraform plan
terraform apply
```

### 4. Deploy Production Environment

```bash
cd environments/prod
terraform init
terraform workspace new prod
terraform plan
terraform apply
```

## Module Documentation

Each module contains:
- `main.tf` - Primary resource definitions
- `variables.tf` - Input variables with descriptions and validation
- `outputs.tf` - Exported values for use in other modules
- `README.md` - Detailed module documentation

## Environment Variables

Required environment variables:
- `AWS_REGION` - AWS region (default: eu-west-2)
- `AWS_PROFILE` - AWS CLI profile name
- `TF_VAR_db_password` - RDS master password (sensitive)

## Cost Estimation

**Development Environment** (minimal):
- VPC: Free
- EC2 (t3.small): ~£15/month
- RDS (db.t3.micro): ~£15/month
- ALB: ~£20/month
- ElastiCache (cache.t3.micro): ~£12/month
- **Total: ~£62/month**

**Production Environment** (HA):
- VPC: Free
- EC2 (t3.medium × 2): ~£60/month
- RDS (db.t3.small, Multi-AZ): ~£60/month
- ALB: ~£20/month
- ElastiCache (cache.t3.small): ~£25/month
- **Total: ~£165/month**

## Security Features

- All resources in private subnets (except ALB)
- Security groups with least privilege rules
- Encryption at rest (RDS, S3)
- Encryption in transit (TLS/SSL)
- IAM roles with minimal permissions
- No hardcoded credentials
- VPC Flow Logs enabled
- CloudWatch monitoring enabled

## Compliance & Governance

- Consistent tagging across all resources
- Resource naming conventions
- Audit logging via CloudTrail
- Access logging for ALB and S3
- Backup policies for RDS

## Disaster Recovery

- RDS automated backups (7-day retention)
- RDS Multi-AZ deployment in production
- S3 versioning enabled
- Cross-region replication (production only)

## Troubleshooting

Common issues and solutions:

1. **State Lock Error**
   ```bash
   terraform force-unlock <LOCK_ID>
   ```

2. **RDS Deletion Protection**
   - Set `deletion_protection = false` in RDS module before destroying

3. **Terraform State**
   - Always commit tfstate to remote backend
   - Never commit tfstate to git

## Next Steps (Phase 2)

After infrastructure is deployed:
1. Configure EC2 instances with Ansible
2. Deploy application code
3. Set up monitoring and logging
4. Implement CI/CD pipeline

## License
MIT License
