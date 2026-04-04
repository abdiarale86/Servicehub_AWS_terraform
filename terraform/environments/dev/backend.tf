terraform {

  backend "s3" {
    bucket         = "terraform-project-a-terraform-state-490004651290"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-project-a-terraform-locks"
    encrypt        = true
  }
}