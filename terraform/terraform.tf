terraform {
  backend "s3" {
    region = "us-east-1"
    bucket = "astounding-terraform-state"
    key = "terraform.tfstate"
    dynamodb_table = "astounding-terraform-state-lock"
    encrypt = true
  }
}