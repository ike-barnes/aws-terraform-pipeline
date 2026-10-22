terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bootstrap runs once, from a laptop. Its own state lives in the
  # shared state bucket in the management account. The bucket name holds
  # an account ID, so it is kept out of the public repo:
  #   terraform init -backend-config=backend.hcl   (see backend.hcl.example)
  backend "s3" {
    key          = "aws-terraform-pipeline/bootstrap/terraform.tfstate"
    region       = "us-east-1"
    profile      = "mgmt"
    encrypt      = true
    use_lockfile = true
  }
}
