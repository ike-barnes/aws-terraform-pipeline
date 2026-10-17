provider "aws" {
  region  = var.region
  profile = "dev" # the pipeline's identity and state live in the dev account

  default_tags {
    tags = {
      Project   = "aws-terraform-pipeline"
      Component = "bootstrap"
      ManagedBy = "terraform"
      Owner     = "ike-barnes"
    }
  }
}

data "aws_caller_identity" "current" {}
