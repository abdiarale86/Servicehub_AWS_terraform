aws_region   = "eu-west-2"
project_name = "terraform-project-a"
environment  = "dev"
vpc_cidr     = "10.0.0.0/16"

ec2_ami_id   = "ami-083d8a6500c1d55d6"
ec2_key_name = "nov25_accessKeys"

common_tags = {
  Project     = "terraform-project-a"
  Environment = "dev"
  ManagedBy   = "Terraform"
  Owner       = "Abdi"
}


# export TF_VAR_db_password='Password123!'