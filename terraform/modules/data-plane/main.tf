# ---------------------------------------------------------------------------
# DATA PLANE (FISMA-High target)
# Customer-managed-key encryption, no public access, full audit logging.
# Generic reference only — no NOAA data or credentials.
# ---------------------------------------------------------------------------

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
}

variable "log_bucket_id" {
  type        = string
  description = "Bucket to receive S3 access logs."
}

data "aws_caller_identity" "current" {}

# Customer-managed key: explicit, rotated, least-privilege.
resource "aws_kms_key" "data" {
  description             = "${var.name_prefix} data-plane CMK"
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

resource "aws_kms_alias" "data" {
  name          = "alias/${var.name_prefix}-data-plane"
  target_key_id = aws_kms_key.data.key_id
}

# Governed object storage for the FISMA-High data plane.
resource "aws_s3_bucket" "data" {
  bucket = "${var.name_prefix}-data-plane"
  # checkov:skip=CKV_AWS_144:Cross-region replication is a production/ATO-time decision;
  # omitted from this single-region reference to keep it deployable as-is.
  # checkov:skip=CKV2_AWS_62:Event notifications are workflow-specific (set per integration).
  # checkov:skip=CKV2_AWS_61:Lifecycle/retention is environment-specific; defined per ATO.
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "data" {
  bucket        = aws_s3_bucket.data.id
  target_bucket = var.log_bucket_id
  target_prefix = "data-plane/"
}

# Enforce TLS-only access (FISMA control: protect data in transit).
resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.data.arn,
        "${aws_s3_bucket.data.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

output "bucket_arn" {
  value = aws_s3_bucket.data.arn
}

output "kms_key_arn" {
  value = aws_kms_key.data.arn
}
