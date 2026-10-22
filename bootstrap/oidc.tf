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

# ---------------------------------------------------------------------
# Permissions boundary: the most any role created by the pipeline can
# ever do. The apply role may only create roles that carry it, so even
# a malicious change can't use the pipeline to mint an admin role.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid = "FlowLogDelivery"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "pipeline-workload-boundary"
  description = "Upper limit for every IAM role created by the Terraform pipeline."
  policy      = data.aws_iam_policy_document.workload_boundary.json
}

# ---------------------------------------------------------------------
# Apply role: can change infrastructure, but only from a job that runs
# in the "production" GitHub environment, which requires a human
# approval and only allows the main branch.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "apply_trust" {
  statement {
    sid     = "GitHubProductionEnvironmentOnly"
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
      values   = ["${local.repo_subject}:environment:production"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "gha-terraform-apply"
  description          = "Assumed by the approval-gated production job in ${local.repo} to run terraform apply."
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

# Read everything, so Terraform can refresh state.
resource "aws_iam_role_policy_attachment" "apply_read_only" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  workload_role_arns = "arn:aws:iam::${local.account_id}:role/pipeline-dev-*"
}

# Write only what the infra/ code manages. Anything else, such as an
# EC2 instance or an S3 bucket, is denied by default.
data "aws_iam_policy_document" "apply_write" {
  statement {
    sid = "ManageNetwork"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageLogKey"
    actions = [
      "kms:CreateKey", "kms:PutKeyPolicy", "kms:EnableKeyRotation",
      "kms:ScheduleKeyDeletion", "kms:TagResource", "kms:UntagResource",
      "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageLogGroups"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
      "logs:AssociateKmsKey", "logs:DisassociateKmsKey",
      "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CreateWorkloadRolesOnlyWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy"]
    resources = [local.workload_role_arns]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid       = "MaintainWorkloadRoles"
    actions   = ["iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy"]
    resources = [local.workload_role_arns]
  }

  statement {
    sid       = "PassWorkloadRolesToFlowLogsOnly"
    actions   = ["iam:PassRole"]
    resources = [local.workload_role_arns]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["vpc-flow-logs.amazonaws.com"]
    }
  }

  statement {
    sid    = "NeverRemoveTheBoundary"
    effect = "Deny"
    actions = ["iam:DeleteRolePermissionsBoundary", "iam:PutRolePermissionsBoundary",
    "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:SetDefaultPolicyVersion"]
    resources = ["*"]
  }

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid     = "ReadWriteStateAndLock"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/infra/terraform.tfstate",
      "${aws_s3_bucket.state.arn}/infra/terraform.tfstate.tflock",
    ]
  }
}

resource "aws_iam_role_policy" "apply_write" {
  name   = "terraform-apply-infra"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_write.json
}
