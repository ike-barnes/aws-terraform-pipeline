# No `profile` here on purpose. In GitHub Actions, credentials come
# from the OIDC role. On a laptop, set AWS_PROFILE=dev before running.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "aws-terraform-pipeline"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "ike-barnes"
    }
  }
}

data "aws_caller_identity" "current" {}
