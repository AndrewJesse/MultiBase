terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {} # configured by scripts/bootstrap.sh via backend.hcl
}

provider "aws" {
  region = var.primary_region
  default_tags {
    tags = { Project = "multibase", Stack = "persistent" }
  }
}

data "aws_caller_identity" "me" {}

locals {
  account_id  = data.aws_caller_identity.me.account_id
  bucket_name = "multibase-pg-backups-${local.account_id}"
}

# ---------- S3 backups ----------
resource "aws_s3_bucket" "backups" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "expire-noncurrent-and-abort-multipart"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

data "aws_iam_policy_document" "backups_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket     = aws_s3_bucket.backups.id
  policy     = data.aws_iam_policy_document.backups_tls_only.json
  depends_on = [aws_s3_bucket_public_access_block.backups]
}

# ---------- Node IAM role (instance profile, no static keys) ----------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "multibase-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "node" {
  statement {
    sid       = "ListBackupBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.backups.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["pg/*", "pg"]
    }
  }
  statement {
    sid       = "ReadWriteBackupPrefix"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.backups.arn}/pg/*"]
  }
  statement {
    sid       = "ReadBootstrapParams"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*:${local.account_id}:parameter/multibase/*"]
  }
}

resource "aws_iam_role_policy" "node" {
  name   = "multibase-node"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.node.json
}

resource "aws_iam_instance_profile" "node" {
  name = "multibase-node"
  role = aws_iam_role.node.name
}

# ---------- Roles Anywhere for the home node (optional) ----------
resource "aws_rolesanywhere_trust_anchor" "home" {
  count   = var.roles_anywhere_ca_pem == "" ? 0 : 1
  name    = "multibase-home"
  enabled = true
  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data { x509_certificate_data = var.roles_anywhere_ca_pem }
  }
}

data "aws_iam_policy_document" "home_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
    principals {
      type        = "Service"
      identifiers = ["rolesanywhere.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "home" {
  count              = var.roles_anywhere_ca_pem == "" ? 0 : 1
  name               = "multibase-home"
  assume_role_policy = data.aws_iam_policy_document.home_assume.json
}

resource "aws_iam_role_policy" "home" {
  count  = var.roles_anywhere_ca_pem == "" ? 0 : 1
  name   = "multibase-node"
  role   = aws_iam_role.home[0].id
  policy = data.aws_iam_policy_document.node.json
}

resource "aws_rolesanywhere_profile" "home" {
  count     = var.roles_anywhere_ca_pem == "" ? 0 : 1
  name      = "multibase-home"
  enabled   = true
  role_arns = [aws_iam_role.home[0].arn]
}

# ---------- Budget ----------
resource "aws_budgets_budget" "monthly" {
  name         = "multibase-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}

# ---------- GitHub Actions OIDC (no long-lived keys in GitHub) ----------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
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
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:pull_request",
        "repo:${var.github_repo}:ref:refs/heads/main",
      ]
    }
  }
}

# Plan-only: read-only AWS plus access to the Terraform state objects.
resource "aws_iam_role" "github_plan" {
  name               = "multibase-github-plan"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

resource "aws_iam_role_policy_attachment" "github_plan_readonly" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_state" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::multibase-tfstate-${local.account_id}/multibase/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::multibase-tfstate-${local.account_id}"]
  }
}

resource "aws_iam_role_policy" "github_state" {
  name   = "tfstate"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_state.json
}
