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

# GitHub repositories created after July 15, 2026 put immutable numeric
# IDs in the OIDC subject claim, so a deleted-and-recreated repo with the
# same name can't inherit this trust. Look them up with:
#   https://api.github.com/repos/<owner>/<repo>  (fields: owner.id, id)
variable "github_owner_id" {
  description = "Numeric GitHub ID of the repository owner."
  type        = string
  default     = "170377948"
}

variable "github_repo_id" {
  description = "Numeric GitHub ID of the repository."
  type        = string
  default     = "1423779068"
}
