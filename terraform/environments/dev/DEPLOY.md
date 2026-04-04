# 🚀 Terraform-Project-A AWS Deployment Guide

## Prerequisites Checklist

- [ ] AWS CLI installed and configured
- [ ] Terraform 1.5+ installed
- [ ] AWS account with admin access
- [ ] EC2 key pair created (or will create one)
- [ ] ~£70/month budget for dev environment

---

## Step 1: Verify Prerequisites (2 minutes)

```bash
# Check AWS CLI
aws --version
# Should show: aws-cli/2.x.x

# Check Terraform
terraform version
# Should show: Terraform v1.5+

# Verify AWS credentials
aws sts get-caller-identity
# Should show your account ID and user

# Check available regions
aws ec2 describe-regions --query 'Regions[].RegionName' --output table
```

---

## Step 2: Navigate to Project (1 minute)

```bash
cd ~/home/jama238/terraform-project-a/terraform/environments/dev
```

---

## Step 3: Create EC2 Key Pair (2 minutes)

```bash
# Option A: Create new key pair
aws ec2 create-key-pair \
  --key-name nov25_accesskey \
  --query 'KeyMaterial' \
  --output text \
  --region eu-west-2 > nov25_accesskey.pem

# Set correct permissions
chmod 400 nov25_accesskey.pem

# Verify key was created
aws ec2 describe-key-pairs --key-names nov25_accesskey --region eu-west-2

# Option B: Use existing key pair
# Skip this step if you already have a key pair
```

---

## Step 4: Create Backend (5 minutes)

```bash
# Make script executable
chmod +x setup-backend.sh

# Run backend setup
./setup-backend.sh

# Note the bucket name from output
# Example: terraform-project-a-terraform-state-4900046512555555
```

---

## Step 5: Get Latest AMI ID (1 minute)

```bash
# Get Amazon Linux 2023 AMI ID
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' \
  --output text \
  --region eu-west-2)

echo "AMI ID: $AMI_ID"
# Save this - you'll need it
```

---

## Step 6: Configure terraform.tfvars (3 minutes)

```bash
# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Replace these values:**

```hcl
# AWS Configuration
aws_region   = "eu-west-2"  # London region
project_name = "terraform-project-a"
environment  = "dev"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"

# EC2 Configuration
ec2_ami_id   = "ami-XXXXX"  # Paste AMI ID from Step 5
ec2_key_name = "nov25_accesskey"  # From Step 3

# Common Tags
common_tags = {
  Project     = "terraform-project-a"
  Environment = "dev"
  ManagedBy   = "Terraform"
  Owner       = "abdi"
  CostCenter  = "Development"
}
```

**Save: Ctrl+X, Y, Enter**

---

## Step 7: Set Database Password (1 minute)

```bash
# IMPORTANT: Set secure database password
export TF_VAR_db_password="Password123!"

# Verify it's set
echo $TF_VAR_db_password

# Add to your ~/.zshrc or ~/.bashrc to persist:
echo 'export TF_VAR_db_password="password12345!"' >> ~/.zshrc
```

**⚠️ NEVER commit this password to git!**

---

## Step 8: Update Backend Configuration (2 minutes)

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Edit main.tf
nano main.tf
```

**Find this section (line 10-16) and update the bucket name:**

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-prokect-a-state-REPLACE-WITH-ACCOUNT-ID"  # ← Change this
    key            = "dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-project-a-locks"
    encrypt        = true
  }
}
```

**Replace with:**
```hcl
bucket = "terraform-prokect-a-state-${AWS_ACCOUNT_ID}"
```

**Or manually replace with actual account ID**

**Save: Ctrl+X, Y, Enter**

---

## Step 9: Initialize Terraform (2 minutes)

```bash
# Initialize Terraform
terraform init

# You should see:
# ✅ Terraform has been successfully initialized!
# ✅ Backend configured to use S3
```

**If you see errors:**
- Check AWS credentials: `aws sts get-caller-identity`
- Verify backend bucket exists: `aws s3 ls | grep terraform-project`
- Check region is correct in main.tf

---

## Step 10: Plan Deployment (3 minutes)

```bash
# Generate execution plan
terraform plan -out=tfplan

# Review the output - should show:
# Plan: 30+ to add, 0 to change, 0 to destroy

# Review what will be created:
# - VPC with 6 subnets
# - 2 NAT Gateways
# - Internet Gateway
# - 4 Security Groups
# - Application Load Balancer
# - Auto Scaling Group (1 EC2 instance)
# - RDS PostgreSQL database
# - ElastiCache Redis cluster
# - S3 bucket
# - IAM roles and policies
```

**⚠️ Review costs in output - should be ~£60-70/month**

---

## Step 11: Deploy! (10-15 minutes)

```bash
# Apply the plan
terraform apply tfplan

# OR apply directly (with prompt)
terraform apply

# Type 'yes' when prompted

# ⏳ This will take 10-15 minutes
# You'll see resources being created:
# - VPC resources (2 min)
# - NAT Gateways (3 min)
# - RDS database (8 min) ← longest
# - Everything else (2 min)
```

**☕ Grab coffee while it deploys**

---

## Step 12: Verify Deployment (5 minutes)

```bash
# Get outputs
terraform output

# Should show:
# alb_dns_name = "terraform-project-a-XXXXX.eu-west-2.elb.amazonaws.com"
# rds_endpoint = "terraform-project-a.XXXXX.eu-west-2.rds.amazonaws.com:5432"
# vpc_id = "vpc-XXXXX"

# Save ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)
echo $ALB_DNS

# Wait 2-3 minutes for instances to finish bootstrapping
sleep 180

# Test health endpoint
curl http://${ALB_DNS}/health/health

# Expected: {"status":"healthy","timestamp":1705328914.123}
```

---

## Step 13: Verify in AWS Console (5 minutes)

**Open AWS Console and check:**

1. **VPC** → VPCs
   - Should see: `terraform-project-dev-vpc`
   - 6 subnets (2 public, 2 private-app, 2 private-db)

2. **EC2** → Instances
   - Should see: 1 instance in Auto Scaling Group
   - Status: Running
   - Health checks: 2/2 passing

3. **EC2** → Load Balancers
   - Should see: `terraform-project-a-dev-alb`
   - Target health: Healthy (1 target)

4. **RDS** → Databases
   - Should see: `terraform-project-a-dev-db`
   - Status: Available

5. **ElastiCache** → Redis
   - Should see: `terraform-project-a-dev-redis`
   - Status: Available

6. **Billing** → Cost Explorer
   - Should show: ~£2-3/day

---

## Step 14: Take Screenshots (10 minutes)

**For your Medium article and portfolio:**

1. Architecture diagram from AWS Console:
   - VPC with all subnets
   - Resources map

2. EC2 Dashboard:
   - Running instances
   - Auto Scaling Group

3. Load Balancer:
   - Healthy targets
   - Target group health checks

4. RDS Database:
   - Configuration
   - Monitoring metrics

5. Cost Explorer:
   - Daily costs
   - Service breakdown

6. Terminal output:
   - `terraform apply` success
   - `curl` health check working

---

## Step 15: Test All Endpoints (5 minutes)

```bash
# Set ALB DNS
ALB_DNS=$(terraform output -raw alb_dns_name)

# Health check
curl http://${ALB_DNS}/health/health
# Expected: {"status":"healthy","timestamp":...}

# Readiness check
curl http://${ALB_DNS}/health/ready
# Expected: {"status":"ready","checks":{"database":true,"redis":true}}

# Liveness check
curl http://${ALB_DNS}/health/live
# Expected: {"status":"alive"}

# Metrics
curl http://${ALB_DNS}/metrics | head -20
# Expected: Prometheus metrics

# Register a test user
curl -X POST http://${ALB_DNS}/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "SecurePass123!",
    "full_name": "Test User"
  }'

# Expected: {"message":"User registered successfully","user_id":1}
```

---

## 🎉 SUCCESS! You're Deployed!

### What You Have:
- ✅ Production-grade infrastructure on AWS
- ✅ High availability (Multi-AZ)
- ✅ Auto-scaling (1-3 instances)
- ✅ Load balanced
- ✅ Encrypted storage
- ✅ Private subnets
- ✅ Monitoring ready
- ✅ Cost: ~£60-70/month

### Next Steps:
1. **Write Medium Article 1** (tonight/tomorrow)
2. **Update CV** with this project
3. **Apply to 2-3 jobs** tomorrow
4. **Start Phase 2** (Ansible) this weekend

---

## 💰 Cost Management

### Daily Costs:
- NAT Gateways: £0.90/day (2 × £0.045/hr)
- ALB: £0.50/day
- EC2: £0.35/day (t3.small)
- RDS: £0.35/day (db.t3.micro)
- ElastiCache: £0.28/day (cache.t3.micro)
- **Total: ~£2.40/day (£72/month)**

### To Reduce Costs:
```bash
# Stop instances when not demoing (keeps data)
terraform apply -var="desired_size=0"

# Destroy completely (loses data)
terraform destroy

# Use spot instances (edit ec2 module)
# Single NAT Gateway (edit vpc module)
```

---

## 🔧 Troubleshooting

### Issue: terraform init fails
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify backend bucket exists
aws s3 ls | grep terraform-project-a

# Check region
aws configure get region
```

### Issue: RDS creation times out
```bash
# This is normal - RDS takes 8-10 minutes
# Wait patiently or increase timeout in rds module
```

### Issue: Health check returns 502/503
```bash
# Instance might still be bootstrapping
# Wait 3-5 minutes after terraform completes

# Check instance logs
aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Reservations[*].Instances[*].[InstanceId]' \
  --output text

# Get console output
aws ec2 get-console-output --instance-id i-XXXXX
```

### Issue: Can't connect to RDS
```bash
# Verify security groups allow connection
# RDS should only accept connections from EC2 security group
# This is correct - RDS is in private subnet
```

---

## 🧹 Cleanup (When Done)

```bash
# To avoid charges, destroy resources:
terraform destroy

# Type 'yes' to confirm

# Verify everything is deleted in AWS Console

# Keep S3 bucket and DynamoDB table (free tier, useful for future)
```

---

## 📞 Need Help?

Check logs:
```bash
# Terraform logs
export TF_LOG=DEBUG
terraform apply

# AWS CloudWatch Logs
aws logs tail /aws/ec2/terraform-project-a --follow
```

---

**Ready to deploy? Run the commands step by step!** 🚀
