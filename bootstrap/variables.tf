variable "region" {
  description = "Region for the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository."
  type        = string
  default     = "ike-barnes"
}

variable "github_repo" {
  description = "Repository allowed to assume the pipeline roles."
  type        = string
  default     = "aws-terraform-pipeline"
}
