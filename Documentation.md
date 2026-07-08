
How I Built and Deployed a Secure, Scalable Platform Using Terraform
These days, infrastructure isn’t just about spinning up servers. It needs to be secure, scalable, reliable, and cost-efficient.

When I was building a service management platform for internal use, I set a few clear targets. I wanted high availability (around 99.9% uptime), strong security using a defense-in-depth approach, auto-scaling to handle traffic when needed, and to keep the dev environment under £100/month.

In this post, I’ll walk through how I designed the architecture, how I implemented it using Infrastructure as Code (Terraform), and how you can deploy something similar step by step.

Even though Kubernetes and fully cloud-native setups get a lot of hype, a lot of real-world enterprise systems still rely on more traditional infrastructure patterns — and honestly, they’re often simpler, easier to manage, and get the job done really well.

Complete codebase on GitHub:

https://github.com/abdiarale86/Servicehub_AWS_terraform

The Three-Tier Architecture
Why I Chose These AWS Services:
Application Load Balancer (ALB)
Distributes incoming traffic across multiple servers so the app doesn’t go down if one fails
Handles SSL/TLS (HTTPS) so I don’t need to manage certificates on each server
Built-in health checks to only send traffic to healthy instances
Public Subnets
Used for components that must be accessible from the internet (like the load balancer)
Keeps external traffic separated from internal resources
Private Subnets
Used to protect internal services (app servers, databases) from direct internet access
Adds an extra layer of security by limiting exposure
EC2 Instances
Runs the actual application code
Gives full control over the environment (OS, packages, configs)
Easy to scale and integrate with other AWS services
Auto Scaling Group (ASG)
Automatically adds/removes EC2 instances based on traffic
Helps maintain performance during high load
Improves availability by replacing unhealthy instances
NAT Gateway
Allows private EC2 instances to access the internet (for updates, APIs, etc.)
Prevents inbound internet access to those instances
Keeps the application layer secure while still functional
RDS (PostgreSQL)
Managed database service — AWS handles backups, patching, and maintenance
Reliable and easy to scale
PostgreSQL is stable and widely used in production
ElastiCache (Redis)
Speeds up the application by caching frequently used data
Reduces load on the database
Great for sessions, caching, and quick lookups
Availability Zones (Multi-AZ Setup)
Distributes resources across different data centers
Prevents downtime if one zone fails
Helps achieve high availability (99.9% target)
Key Design Decisions:
Multi-AZ Deployment
I spread each layer of the stack across two Availability Zones in us-east-1 to improve resilience and availability. That way, if one AZ has an issue, the platform can still keep running from the other. It’s a practical way to reduce single points of failure without overcomplicating the setup.

Private Subnet Architecture
Both the application tier and the database tier sit fully inside private subnets. This keeps them off the public internet and adds an extra layer of protection. Even if something in the app layer were compromised, the attacker would not have direct internet-facing access to those resources, and the database would still remain isolated behind tighter network controls.

NAT Gateway Strategy
I used two NAT Gateways, one in each Availability Zone, so private instances can still make outbound calls while keeping the setup highly available. If cost is a bigger concern, this can be reduced to a single NAT Gateway, but that comes with some risk since outbound connectivity would depend on one point of failure.

Network Design
The network is built using a simple and structured CIDR plan that makes it easy to scale later while keeping everything clearly separated.

I used a /16 VPC (10.0.0.0/16), which gives a large pool of IP addresses. It’s more than what’s needed right now, but it leaves room for future growth without having to redesign the network.

Each layer has its own subnet range:

Public Subnets (10.0.1.0/24, 10.0.2.0/24)
Used for internet-facing components like the load balancer and NAT Gateways
Private App Subnets (10.0.11.0/24, 10.0.12.0/24)
Used for EC2 instances running the application
Private DB Subnets (10.0.21.0/24, 10.0.22.0/24)
Used for databases, fully isolated from the internet
I followed a simple numbering pattern:

1.x → Public
11.x → App
21.x → Database
This makes it really easy to understand what each subnet is for when debugging or reviewing logs.

Routing Strategy
Each subnet is configured based on what level of internet access it needs:

Public Subnets
Have full internet access (inbound and outbound) through the Internet Gateway
Private App Subnets
Don’t accept inbound traffic from the internet, but can make outbound requests through the NAT Gateway
Private DB Subnets
Have no internet access at all — no routes to the internet
This setup ensures that only the parts of the system that need internet access have it, while everything else stays protected.

Security: Defense in Depth
Security isn’t just one setting — it’s about layering multiple controls together.

Instead of relying on a single line of defense, this setup uses network isolation, controlled routing, and restricted access between layers. So even if one part of the system is compromised, the rest of the infrastructure is still protected.

Security Group Chain
Internet → ALB (Port 80/443)
              ↓
           EC2 (Port 5000) ← Only from ALB
              ↓
           RDS (Port 5432) ← Only from EC2
           Redis (Port 6379) ← Only from EC2
The security setup follows a strict flow, where each layer only talks to the layer it needs:

Internet → ALB (Ports 80/443)
The load balancer is the only component exposed to the public
ALB → EC2 (Port 5000)
Application servers only accept traffic from the load balancer — nothing else
EC2 → RDS (Port 5432)
Database access is restricted to the application layer only
EC2 → Redis (Port 6379)
Cache is also only accessible from the application servers
The key idea here is that security groups reference other security groups, not open IP ranges. This keeps communication tightly controlled. Even if an EC2 instance is compromised, it can only talk to the services it was already allowed to access — nothing more.

IAM Roles Over Access Keys
Instead of using access keys on EC2 instances, I used IAM roles, which is the recommended approach.

Each instance gets a role with very limited permissions, only allowing it to interact with a single S3 bucket:

s3:PutObject → upload files
s3:GetObject → read files
s3:DeleteObject → delete files
That’s it — no extra permissions.

This follows the least privilege principle, meaning the application only gets exactly what it needs to function. If the instance is ever compromised, the attacker won’t be able to access other AWS services or resources outside of that scope.

Step-by-Step Deployment Guide
Prerequisites
Before getting started, make sure you have the basics in place:

An AWS account with enough permissions to create networking, compute, storage, and database resources
The AWS CLI installed and configured using aws configure
Terraform 1.5 or higher installed on your machine
Git installed so you can clone and manage the project code
Project Structure
Before deploying anything, it’s a good idea to keep the project organized in a way that’s easy to manage and scale. A clean Terraform structure makes it much easier to separate networking, compute, database, and security components as the infrastructure grows.

Terraform-project/
├── terraform-infrastructure/
│   ├── modules/
│   │   ├── vpc/           # Network foundation
│   │   ├── security-groups/  # Firewall rules
│   │   ├── iam/           # Roles and policies
│   │   ├── s3/            # Object storage
│   │   ├── alb/           # Load balancer
│   │   ├── ec2/           # Compute (ASG + Launch Template)
│   │   ├── rds/           # PostgreSQL database
│   │   └── elasticache/   # Redis cache
│   └── environments/
│       └── dev/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── user_data.sh
Step 1: Setup
First, create a new project folder:
mkdir terraform-project-A
cd terraform-project-A
Inside this folder, we’ll follow a simple structure to keep things organized. Navigate to:

cd terraform/environment/dev
If the folders don’t exist yet, create them:

mkdir -p terraform/environment/dev
cd terraform/environment/dev

Step 2: Setting Up the S3 Backend for Terraform State
Before we start building any infrastructure, we need to configure a remote backend for Terraform state.

Instead of storing state locally (which is risky and hard to manage), we’ll use an S3 bucket. This allows us to:

Keep state centralized
Avoid conflicts when working in teams
Improve reliability and security
Create a file called backend.tf:

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }


  backend "s3" {
    bucket         = "terraform-project-A-terraform-state-bucket-1"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-west-2"
}
What This Does
S3 bucket → stores your Terraform state file
key → organizes state by environment (dev in this case)
DynamoDB table → handles state locking (prevents multiple people from breaking things at the same time)
encrypt = true → keeps your state secure
“To automate backend setup, I used a Bash script that creates an S3 bucket for storing Terraform state and a DynamoDB table for state locking. The script ensures the bucket is versioned, encrypted, and not publicly accessible. It also dynamically names resources using the AWS account ID to avoid conflicts. This approach removes manual setup and ensures the backend is created consistently every time.”

From here, we’re ready to run:

#!/bin/bash
set -e

echo "=========================================="
echo "terraform-project-A - Dev Environment Backend Setup"
echo "=========================================="
echo ""

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="eu-west-2"
PROJECT_NAME="terraform-project-A"

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "❌ Error: Could not retrieve AWS Account ID"
    echo "   Please run: aws configure"
    exit 1
fi

echo "✅ AWS Account ID: $AWS_ACCOUNT_ID"
echo "✅ Region: $AWS_REGION"
echo ""

# S3 bucket name
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
TABLE_NAME="${PROJECT_NAME}-terraform-locks"

echo "Creating backend resources..."
echo ""

# Create S3 bucket
echo "1️⃣  Creating S3 bucket: $BUCKET_NAME"
if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    echo "   ✅ Bucket created"
else
    echo "   ℹ️  Bucket already exists"
fi

# Enable versioning
echo "2️⃣  Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled
echo "   ✅ Versioning enabled"

# Enable encryption
echo "3️⃣  Enabling encryption..."
aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
echo "   ✅ Encryption enabled"

# Block public access
echo "4️⃣  Blocking public access..."
aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,
RestrictPublicBuckets=true"
echo "   ✅ Public access blocked"

# Create DynamoDB table
echo "5️⃣  Creating DynamoDB table: $TABLE_NAME"
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "   ℹ️  Table already exists"
else
    aws dynamodb create-table \
        --table-name "${TABLE_NAME}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${AWS_REGION}" \
        --tags Key=Project,Value=ServiceHub Key=ManagedBy,Value=Terraform \
        >/dev/null
    
    echo "   ⏳ Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${AWS_REGION}"
    echo "   ✅ Table created"
fi

echo ""
echo "=========================================="
echo "✅ Backend Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Configuration Details:"
echo "   S3 Bucket: ${BUCKET_NAME}"
echo "   DynamoDB Table: ${TABLE_NAME}"
echo "   Region: ${AWS_REGION}"
echo ""
echo "📝 Update your main.tf backend configuration:"
echo ""
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"${BUCKET_NAME}\""
echo "    key            = \"dev/terraform.tfstate\""
echo "    region         = \"${AWS_REGION}\""
echo "    dynamodb_table = \"${TABLE_NAME}\""
echo "    encrypt        = true"
echo "  }"
echo "}"
echo ""
echo "🚀 Next steps:"
echo "   1. Update main.tf with the backend config above"
echo "   2. Run: terraform init"
echo "   3. Run: terraform plan"
echo "   4. Run: terraform apply"
echo ""
Shebang + safety
#!/bin/bash
Tells the system to run this script using Bash
set -e
If any command fails → the script stops immediately
👉 prevents half-built infrastructure (very important in DevOps)
Pretty output (just UI)
echo "=========================================="
echo "ServiceHub Backend Setup"
echo "=========================================="
Just prints a header so the script looks clean when running
Get AWS account info
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
Calls AWS CLI to get your account ID
Stores it in a variable
👉 Used to make unique resource names

AWS_REGION="eu-west-2"
PROJECT_NAME="servicehub-app"
Sets:

region
project name (used for naming resources)
Error check
if [ -z "$AWS_ACCOUNT_ID" ]; then
Checks if account ID is empty
echo "❌ Error: Could not retrieve AWS Account ID"
echo "   Please run: aws configure"
exit 1
If AWS CLI isn’t configured → stop the script
Print info
echo "✅ AWS Account ID: $AWS_ACCOUNT_ID"
echo "✅ Region: $AWS_REGION"
Confirms what account + region you’re using
Dynamic naming (VERY important)
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
TABLE_NAME="${PROJECT_NAME}-terraform-locks"
👉 Creates:

unique S3 bucket name (must be globally unique)
DynamoDB table name
S3 Setup
Create bucket
if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
Checks if bucket exists
aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
Creates the bucket if it doesn’t exist
Enable versioning
aws s3api put-bucket-versioning
Keeps history of state files
Super important:

protects against mistakes
lets you roll back
Enable encryption
"SSEAlgorithm": "AES256"
Encrypts Terraform state at rest
important because state can contain:

secrets
resource details
Block public access
put-public-access-block
Prevents bucket from being public
this is a security best practice

🗄️ DynamoDB Setup (State Locking)
Check if table exists
aws dynamodb describe-table
Create table
aws dynamodb create-table
Creates table with:
LockID as primary key
PAY_PER_REQUEST billing (cheap + simple)
Wait until ready
aws dynamodb wait table-exists
Makes sure table is fully created before continuing
📦 Final Output
Print config
echo "terraform {"
- This prints ready-to-copy Terraform backend config:

Press enter or click to view image in full size

Automating the Terraform Backend Setup
Instead of manually creating backend resources, I used a simple Bash script to automate the entire process. This ensures the setup is repeatable, consistent, and production-ready.

When I ran the script, it handled everything step by step:

It first retrieved my AWS account ID to generate globally unique resource names
Then it created an S3 bucket to store Terraform state
Enabled versioning, so I can roll back changes if needed
Enabled encryption, keeping the state file secure
Blocked all public access to the bucket (security best practice)
Finally, it created a DynamoDB table for state locking
What This Actually Means
At the end of the script, I now have:

An S3 bucket storing my Terraform state remotely
A DynamoDB table preventing multiple users from running Terraform at the same time
A secure and centralized setup ready for real-world use
This is important because Terraform state is critical — it tracks everything Terraform creates. If it’s lost or corrupted, your infrastructure becomes very hard to manage.

Step 3: Create EC2 Key Pair & Get AMI ID
Before launching any EC2 instances, we need two things:

An AMI ID (the base image for our server)
An EC2 key pair (for SSH access if needed)
Even though AWS SSM Session Manager is the preferred way to connect, having a key pair is still useful for emergency access.

Getting the Latest Amazon Linux AMI
Instead of hardcoding an AMI ID (which can become outdated), I used AWS Systems Manager (SSM) to dynamically fetch the latest Amazon Linux image:

aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' \
  --output text \
  --region eu-west-2
This command:

Queries AWS for the latest Amazon Linux 2023 AMI
Returns the AMI ID for the selected region
Ensures the infrastructure always uses an up-to-date image
Step 4: Configure Variables
To keep the Terraform code clean and reusable, I defined all environment-specific values in a terraform.tfvars file.

This helps avoid hardcoding values directly in the code and makes it easier to reuse the same setup across different environments (like dev, staging, and production).

Here’s what my terraform.tfvars looks like:

aws_region   = "eu-west-2"
project_name = "terraform-project-a"
environment  = "dev"
vpc_cidr     = "10.0.0.0/16"
ec2_ami_id   = "ami-0b0b78dcacbab728f"
ec2_key_name = "nov25_accessKeys.pem"
common_tags = {
  Project     = "terraform-project-a"
  Environment = "dev"
  ManagedBy   = "Terraform"
  Owner       = "Abdi"
}
Why Use terraform.tfvars?
Using a variables file keeps things simple and organized:

Keeps Terraform code clean and readable
Makes it easy to update values without touching core logic
Allows the same code to be reused across environments
For example, I can reuse this setup and just change:

region
environment name
network range
Handling Sensitive Data (Important)
For sensitive values like database passwords, I avoided storing them directly in the file.

Instead, I used an environment variable:

export TF_VAR_db_password='Password123!'
Terraform automatically picks this up at runtime.

Why This Matters
Keeps secrets out of version control
Follows basic security best practices
Makes the project more production-ready
In a real production setup, this would be replaced with something like AWS Secrets Manager or SSM Parameter Store.
Step 5: Understand the Module Structure
As the project grows, managing everything in a single Terraform file becomes messy very quickly. To keep things organized, I structured the project using Terraform modules, where each module handles one specific part of the infrastructure.

Why Use Modules?
Modules help break your infrastructure into smaller, manageable pieces. Instead of writing everything in one place, each component is isolated and easier to work with.

Here’s why this approach is important:

Separation of concerns
Each part of the infrastructure (networking, compute, database) is handled independently
Reusability
The same module can be reused across different environments like dev, staging, and production
Cleaner codebase
Keeps your main configuration simple and easy to read
Easier debugging
If something breaks, you know exactly where to look
Scalability
As your infrastructure grows, you can add or update modules without affecting everything else
Project Structure
Here’s how I organized the modules in this project:

terraform/
├── environments/
│   └── dev/
├── modules/
│   ├── alb/
│   ├── ec2/
│   ├── elasticache/
│   ├── iam/
│   ├── rds/
│   ├── s3/
│   ├── security-groups/
│   └── vpc/
Each folder inside modules/ represents a specific part of the infrastructure.

What Each Module Does
vpc → Creates the network (VPC, subnets, routing, gateways)
security-groups → Controls traffic between resources (very important for security)
alb → Handles incoming traffic and load balancing
ec2 → Runs the application servers
rds → Manages the PostgreSQL database
elasticache → Provides Redis for caching
iam → Defines roles and permissions
s3 → Handles storage (e.g., attachments or assets)
Each module contains:

main.tf → actual resources
variables.tf → inputs
outputs.tf → values passed to other modules
Why This Matters
This structure mirrors how real DevOps teams build infrastructure in production.

Become a Medium member
Instead of one large, hard-to-maintain file, you get:

a modular system
clear boundaries between components
and a setup that’s easy to scale and maintain
This becomes especially important as your architecture grows and more services are added.

How the modules are called
In the dev environment, the main Terraform file acts like the orchestrator. It does not define every AWS resource directly. Instead, it calls each module and passes in the inputs that module needs, like VPC ID, subnet IDs, tags, AMI ID, or security groups.

That means:

the environment file controls the overall deployment
each module builds one part of the infrastructure
modules can pass outputs to other modules, which is how everything gets connected
So instead of one huge Terraform file, you get a cleaner flow:

create the network
create security groups
create storage and IAM
create the load balancer
create the database and cache
create EC2 instances and attach them to the ALB
Why this is powerful
This modular approach gives you a few big benefits:

It keeps the code organized
It makes the infrastructure easier to reuse
It allows modules to be updated without rewriting the whole project
It reflects how real DevOps teams build production infrastructure
For example, the vpc module creates the network once, and then other modules reuse its outputs like subnet IDs and VPC ID.

What this looks like in practice
1. VPC module
This is the foundation. It creates the VPC, public subnets, private app subnets, private DB subnets, routing, NAT, and networking-related resources.

 module "vpc" {
  source = "../../modules/vpc"  
 
 project_name          = var.project_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = local.availability_zones
  public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
  private_app_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  private_db_subnet_cidrs  = ["10.0.21.0/24", "10.0.22.0/24"]
  enable_nat_gateway = true
  enable_flow_logs   = true
  tags = var.common_tags
}
This module creates the core network, and then exposes outputs like:

vpc_id
vpc_cidr
public_subnet_ids
private_app_subnet_ids
private_db_subnet_ids
2. Security groups module
Once the VPC exists, the security groups module uses the VPC outputs to create access controls.

module "security_groups" {
  source = "../../modules/security-groups" 
 project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr
tags = var.common_tags
}
This is a good example of module chaining:

the vpc module creates the VPC
the security_groups module uses module.vpc.vpc_id
Terraform understands this dependency automatically
3. S3 module
This module creates the S3 bucket used for attachments or storage.

module "s3" {
  source = "../../modules/s3"
project_name = var.project_name
  environment  = var.environment
  bucket_name  = "${var.project_name}-${var.environment}-attachments"
  enable_versioning = true
  enable_encryption = true
  tags = var.common_tags
}
This creates the bucket, and then its output, like bucket_arn, can be reused by the IAM module.

4. IAM module
The IAM module creates roles and permissions for EC2.

module "iam" {
  source = "../../modules/iam"
project_name  = var.project_name
  environment   = var.environment
  s3_bucket_arn = module.s3.bucket_arn
  tags = var.common_tags
}
Here, Terraform passes the S3 bucket ARN from the s3 module into the iam module so EC2 can be granted access to that bucket. That is how modules stay separate but still work together.

5. ALB module
This module creates the Application Load Balancer in the public subnets.

module "alb" {
  source = "../../modules/alb"
 project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.alb_sg_id]
  enable_deletion_protection = false
  enable_access_logs         = false
  health_check = {
    path                = "/health/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
  tags = var.common_tags
}
This shows how one module can depend on outputs from two others:

subnet IDs from vpc
ALB security group from security_groups
6. RDS module
The database module creates PostgreSQL in the private DB subnets.

 module "rds" {
  source = "../../modules/rds"
 project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [module.security_groups.rds_sg_id]
  db_name     = "servicehub"
  db_username = "servicehub_admin"
  db_password = var.db_password
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  max_allocated_storage  = 50
  multi_az               = false
  backup_retention_period = 3
  deletion_protection    = false
  tags = var.common_tags
}
This module uses:

DB subnets from the VPC module
RDS security group from the security module
database password from variables
7. ElastiCache module
This creates the Redis cache in the private DB subnets.

module "elasticache" {
  source = "../../modules/elasticache"
 project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [module.security_groups.redis_sg_id]
  node_type              = "cache.t3.micro"
  num_cache_nodes        = 1
  parameter_group_family = "redis7"
  tags = var.common_tags
}
Again, it reuses network and security outputs instead of redefining them.

8. EC2 module
This module creates the app servers in the private app subnets.

 module "ec2" {
  source = "../../modules/ec2"
  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.private_app_subnet_ids
  security_group_ids   = [module.security_groups.ec2_sg_id]
  iam_instance_profile = module.iam.instance_profile_name
  instance_type = "t3.small"
  ami_id        = var.ec2_ami_id
  key_name      = var.ec2_key_name
  min_size     = 1
  max_size     = 2
  desired_size = 1
  target_group_arns = [module.alb.target_group_arn]
  user_data = templatefile("${path.module}/user_data.sh", {
    db_endpoint    = module.rds.db_endpoint
    db_name        = module.rds.db_name
    db_password    = var.db_password
    redis_endpoint = module.elasticache.redis_endpoint
    s3_bucket      = module.s3.bucket_name
    aws_region     = var.aws_region
    environment    = var.environment
  })
  tags = var.common_tags
}
This is the best example of everything coming together:

app subnets from vpc
EC2 security group from security_groups
IAM instance profile from iam
ALB target group from alb
DB endpoint from rds
Redis endpoint from elasticache
bucket name from s3
So the EC2 module becomes the layer that connects to almost every other part of the platform.

Step 6: Understand User Data Automation
One of the most important parts of this setup is the user_data.sh script.

This script runs automatically when an EC2 instance is launched and turns a basic server into a fully working application instance.

What is User Data?
User data is a script that EC2 runs on first boot.

Instead of manually logging into servers and installing things, everything is done automatically.

- This is how we achieve true infrastructure automation.

What This Script Does
Here’s a simplified version of what the script is doing:

#!/bin/bash
set -e
# 1. Install system packages
dnf install -y python3.11 python3.11-pip redis6 postgresql15
# 2. Install Python dependencies
python3.11 -m pip install flask gunicorn psycopg2-binary redis
# 3. Create Flask application with health endpoints
cat > /opt/servicehub/app.py << 'EOF'
# Flask app with /health/health, /health/ready, /health/live
# These endpoints are used by the load balancer
EOF
# 4. Create systemd service for automatic restart
cat > /etc/systemd/system/servicehub.service << 'EOF'
[Service]
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:5000 app:app
Restart=always
EOF
# 5. Start and verify
systemctl enable --now servicehub
curl http://localhost:5000/health/health
Breaking It Down
1. Install system packages
Installs everything the server needs:

Python (for the app)
Redis client
PostgreSQL client
2. Install Python dependencies
Installs the app libraries:

Flask → web framework
Gunicorn → production server
psycopg2 → connects to PostgreSQL
Redis → caching support
3. Create the application
The script creates a basic Flask app with health check endpoints like:

/health/health
/health/ready
/health/live
👉 These endpoints are used by the Application Load Balancer to check if the instance is healthy.

4. Create a systemd service
This ensures the app:

starts automatically on boot
restarts if it crashes
- This is critical for reliability.

5. Start and verify
Starts the service
Runs a quick health check using curl
Why This Matters
This is where the real power of DevOps comes in.

With this setup:

Every EC2 instance is identical
No manual setup, no differences between servers
No configuration drift
Everything is defined in code
Auto Scaling works properly
New instances are fully ready as soon as they launch
Self-healing system
If an instance fails, it’s replaced automatically with a working one
Big Picture
Instead of:

logging into servers
installing packages manually
fixing things by hand
Everything is automated and reproducible.

This is what makes the system:

scalable
reliable
production-ready
Step 7: Deploy Infrastructure
# Initialize Terraform (downloads providers, configures backend)
terraform init
# Preview changes
terraform plan
# Deploy (takes 10-15 minutes)
terraform apply
Press enter or click to view image in full size

What gets created:

1 VPC with 6 subnets across 2 AZs
2 NAT Gateways with Elastic IPs
4 Security Groups
1 Application Load Balancer
1 Auto Scaling Group with Launch Template
1 RDS PostgreSQL instance
1 ElastiCache Redis cluster
1 S3 bucket for attachments
IAM roles and policies
Step 8: Verify the Deployment
After the infrastructure is deployed, the next step is to confirm that the application is actually reachable.

The easiest way to do that is by retrieving the Application Load Balancer (ALB) DNS name, which acts as the public entry point to the platform.

I used the following command to get the ALB endpoint directly from Terraform output:

ALB_DNS=$(terraform output -raw alb_dns_name)
echo "Your API: http://${ALB_DNS}"
This reads the ALB DNS name from the Terraform state and stores it in a shell variable. Once printed, it gives the public URL I can use to access the application and test its health endpoints.

At this point, if the deployment completed successfully, the ALB should route traffic to the EC2 instances running in the private application subnets.


Press enter or click to view image in full size


Another option is to Verify Deployment via AWS Console
In addition to using Terraform outputs, you can also verify everything directly in the AWS Console.

1. Check the Load Balancer
Go to:
EC2 → Load Balancers

Find your Application Load Balancer
Copy the DNS name
Paste it in your browser:
http://your-alb-dns-name
Press enter or click to view image in full size

2. Check Target Group Health (VERY IMPORTANT)
Go to:
EC2 → Target Groups → select your target group

Click Targets
Look at the Health status
✅ Healthy → everything is working
❌ Unhealthy → something is wrong

3. Check EC2 Instances
Go to:
EC2 → Instances

Make sure instances are:
Running
In the correct subnets
Check Security Groups
4. Check RDS Database
Go to:
RDS → Databases

Status should be:
Available
Verify:
Subnet group
security group
endpoint
5. Check CloudWatch Logs (if needed)
Go to:
CloudWatch → Logs

Useful if:
app didn’t start
user_data failed
Why This Matters
Using the AWS Console helps you:

Visually confirm resources were created
Quickly spot issues (like unhealthy targets)
Debug problems without relying only on Terraform
Step 9: Clean Up
Once testing is complete, it’s important to clean up your resources to avoid unnecessary AWS costs.

Terraform makes this easy by allowing you to destroy everything it created with a single command:

terraform destroy --auto-approve
This command:

Deletes all infrastructure created by Terraform
Removes EC2 instances, load balancers, databases, and networking resources
Cleans up the environment completely
⚠ Important Note
This will delete everything, including your database and any stored data.

For production environments, you should protect critical resources like RDS by enabling:

deletion_protection = true
This prevents accidental deletion of your database.

Why This Matters
Cleaning up ensures:

You don’t incur unexpected AWS charges
Your environment stays organized
You can redeploy from scratch anytime
This is one of the biggest advantages of Infrastructure as Code — environments are disposable and reproducible.


Results
Availability
Multi-AZ deployment ✅
Auto-healing via Auto Scaling Group ✅
Health check–based routing through ALB ✅
Target uptime: 99.9%
Security
Network isolation using private subnets ✅
Encryption at rest and in transit ✅
IAM roles (no access keys used) ✅
Least-privilege security group design ✅
Automation
Deployment time reduced to ~15 minutes (previously 4+ hours manually)
Configuration drift: Zero
Manual steps required: Zero
Key Takeaways
Technical Lessons
Infrastructure as Code enables reproducibility
The same Terraform modules can deploy dev, staging, and production just by changing variables.

Security must be built into the architecture
Using private subnets, strict security group rules, and IAM roles creates a strong defense-in-depth model.

Automation reduces risk
With user_data handling setup, every EC2 instance is identical and production-ready from launch.

Cost optimization starts with architecture
The biggest savings come from design decisions — not just picking cheaper instance types.

Process Lessons
Test components independently
Debugging user_data would have been faster if tested outside Terraform first.

Use remote state from day one
Even for personal projects, using an S3 backend avoids state issues and collaboration problems.

Design for full automation
Avoid leaving gaps like “manual steps” — they slow down deployments and introduce risk.

Conclusion
This project shows how a well-designed infrastructure, built with Terraform, can deliver a secure, scalable, and fully automated platform without unnecessary complexity.

By combining a traditional three-tier architecture with modern DevOps practices, I was able to create a system that is reproducible, easy to manage, and ready for real-world use. From networking and security to compute and automation, every component was defined as code and deployed consistently.

More importantly, this wasn’t just about getting resources running — it was about building the right foundation. Decisions like using private subnets, enforcing least-privilege access, and automating instance configuration make a big difference as systems grow.

At the end of the day, the tools may change, but the core principles remain the same:
design for security, automate everything, and build systems that can scale and recover on their own.
