# GitHub Actions proves who it is with a short-lived OIDC token. AWS
# trusts GitHub's token issuer, and each role decides exactly which
# repository and which kind of event may assume it. No access keys exist.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  repo = "${var.github_owner}/${var.github_repo}"

  # Immutable subject format: repo:OWNER@OWNER_ID/REPO@REPO_ID:<context>
  repo_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
}

# ---------------------------------------------------------------------
# Plan role: read-only. Only pull requests in this one repository can
# assume it. A fork, another repo, or a push to a branch gets nothing.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    sid     = "GitHubPullRequestsOnly"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_subject}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "gha-terraform-plan"
  description          = "Assumed by GitHub Actions pull requests in ${local.repo} to run terraform plan."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

# Plan needs to read every resource Terraform manages.
resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Plan reads the state file and takes the lock, but can never
# overwrite state. Only the lock file is writable.
data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/infra/terraform.tfstate"]
  }

  statement {
    sid       = "ManageLockFile"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/infra/terraform.tfstate.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state-read-and-lock"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}
