variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "servicehub"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "ec2_ami_id" {
  description = "AMI ID for EC2 instances (RHEL/Amazon Linux)"
  type        = string
  # Use data source or SSM parameter in production
}

variable "ec2_key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "ServiceHub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
