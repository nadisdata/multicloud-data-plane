# ---------------------------------------------------------------------------
# Landing zone composition: data plane (FISMA-High) + science development
# (FISMA-Moderate) + public access (NODD pattern).
#
# Generic reference. In production these modules deploy across separate
# accounts/subscriptions (AWS GovCloud / Azure Government) on FedRAMP
# Moderate services, with control mappings to NIST SP 800-53.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# Dedicated CMK for the central log bucket.
resource "aws_kms_key" "logs" {
  description             = "${var.name_prefix} access-logs CMK"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableRootAccountAdmin"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

# Central log bucket for access logging across the landing zone.
resource "aws_s3_bucket" "logs" {
  bucket = "${var.name_prefix}-access-logs"
  # checkov:skip=CKV_AWS_144:Cross-region replication is out of scope for this
  # single-region reference; production deploys enable it via a replication module.
  # checkov:skip=CKV2_AWS_62:Event notifications not required for a log archive bucket.
  # checkov:skip=CKV2_AWS_61:Lifecycle/retention is environment-specific; set per ATO.
  # checkov:skip=CKV_AWS_18:This IS the access-log target; it does not log to itself.
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

module "data_plane" {
  source        = "./modules/data-plane"
  name_prefix   = var.name_prefix
  log_bucket_id = aws_s3_bucket.logs.id
}

module "sci_dev" {
  source                 = "./modules/sci-dev"
  name_prefix            = var.name_prefix
  data_plane_bucket_arn  = module.data_plane.bucket_arn
  trusted_principal_arns = var.sci_dev_principal_arns
}

module "public_access" {
  source        = "./modules/public-access"
  name_prefix   = var.name_prefix
  log_bucket_id = aws_s3_bucket.logs.id
}
