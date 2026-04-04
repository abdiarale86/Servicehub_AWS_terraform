/**
 * Development Environment
 * Deploys ServiceHub infrastructure in development configuration
 */

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "abdi"
    }
  }
}

locals {
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.availability_zones

  public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
  private_app_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  private_db_subnet_cidrs  = ["10.0.21.0/24", "10.0.22.0/24"]

  enable_nat_gateway = true
  enable_flow_logs   = true

  tags = var.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "../../modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr

  tags = var.common_tags
}

# S3 Module for Attachments
module "s3" {
  source = "../../modules/s3"

  project_name = var.project_name
  environment  = var.environment
  bucket_name  = "${var.project_name}-${var.environment}-attachments"

  enable_versioning = true
  enable_encryption = true

  tags = var.common_tags
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  project_name  = var.project_name
  environment   = var.environment
  s3_bucket_arn = module.s3.bucket_arn

  tags = var.common_tags
}

# Application Load Balancer Module
module "alb" {
  source = "../../modules/alb"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.alb_sg_id]

  enable_deletion_protection = false # Set true in production
  enable_access_logs         = false # Enable in prod with S3 bucket

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

# RDS PostgreSQL Module
module "rds" {
  source = "../../modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [module.security_groups.rds_sg_id]

  db_name     = "terraformpostgres"
  db_username = "dbadmin"
  db_password = var.db_password # Pass via TF_VAR_db_password

  instance_class        = "db.t3.micro" # Small for dev
  allocated_storage     = 20
  max_allocated_storage = 50

  multi_az                = false # Single AZ for dev
  backup_retention_period = 3
  deletion_protection     = false # Set true in production

  tags = var.common_tags
}

# ElastiCache Redis Module
module "elasticache" {
  source = "../../modules/elasticache"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [module.security_groups.redis_sg_id]

  node_type              = "cache.t3.micro" # Small for dev
  num_cache_nodes        = 1                # No replication for dev
  parameter_group_family = "redis7"

  tags = var.common_tags
}

# EC2 Launch Template Module
module "ec2" {
  source = "../../modules/ec2"

  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.private_app_subnet_ids
  security_group_ids   = [module.security_groups.ec2_sg_id]
  iam_instance_profile = module.iam.instance_profile_name

  instance_type = "t2.micro"     # Small for dev
  ami_id        = var.ec2_ami_id # Use data source or parameter
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
