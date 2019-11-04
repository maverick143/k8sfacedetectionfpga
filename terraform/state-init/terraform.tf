# This terraform module will create state buckets in S3

provider "aws" {
  region = "us-east-1"
}

module "terraform_state_backend" {
  source        = "git::https://github.com/cloudposse/terraform-aws-tfstate-backend.git?ref=0.9.0"
  name          = "astounding-terraform"
  region        = "us-east-1"
}