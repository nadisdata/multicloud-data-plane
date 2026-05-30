# ---------------------------------------------------------------------------
# PUBLIC ACCESS LAYER (NOAA Open Data Dissemination pattern)
# Read-only, curated open-data bucket. Datasets are promoted here by an
# explicit, logged, one-way workflow from the protected plane.
# ---------------------------------------------------------------------------

variable "name_prefix" {
  type = string
}

variable "log_bucket_id" {
  type        = string
  description = "Bucket to receive access logs for the public open-data bucket."
}

resource "aws_s3_bucket" "public" {
  bucket = "${var.name_prefix}-public-open-data"
  # This bucket intentionally serves public open data (NOAA NODD pattern). The
  # following Checkov controls are knowingly accepted for THIS bucket only; the
  # protected data plane (FISMA-High) enforces all of them. Documented, scoped
  # exceptions — not scanner suppression.
  # checkov:skip=CKV_AWS_20:Public READ is the intended function of an open-data bucket.
  # checkov:skip=CKV2_AWS_6:Public access block is intentionally relaxed (see below) to allow public reads.
  # checkov:skip=CKV_AWS_56:restrict_public_buckets is intentionally false to serve open data.
  # checkov:skip=CKV_AWS_54:block_public_policy is intentionally false to attach a public-read policy.
  # checkov:skip=CKV_AWS_70:A public-read Principal is required for open data; writes remain denied.
  # checkov:skip=CKV_AWS_144:Cross-region replication is an ATO-time decision for public data.
  # checkov:skip=CKV2_AWS_62:Event notifications are workflow-specific.
  # checkov:skip=CKV2_AWS_61:Lifecycle/retention is environment-specific.
}

# Public READ is intentional here (open data), but writes stay locked down
# and ACLs are disabled — publishing is done by the promotion pipeline only.
resource "aws_s3_bucket_public_access_block" "public" {
  # checkov:skip=CKV_AWS_54:Intentionally false so a public-read bucket policy can attach (open data).
  # checkov:skip=CKV_AWS_56:Intentionally false to serve open data publicly (NODD pattern).
  bucket                  = aws_s3_bucket.public.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

# Even public data is encrypted at rest and versioned, and the bucket logs access.
resource "aws_s3_bucket_server_side_encryption_configuration" "public" {
  bucket = aws_s3_bucket.public.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "public" {
  bucket = aws_s3_bucket.public.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "public" {
  bucket        = aws_s3_bucket.public.id
  target_bucket = var.log_bucket_id
  target_prefix = "public-open-data/"
}

resource "aws_s3_bucket_ownership_controls" "public" {
  bucket = aws_s3_bucket.public.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  # checkov:skip=CKV_AWS_70:A wildcard Principal is required for public open-data reads;
  # the policy restricts it to s3:GetObject over TLS only, and denies everything else.
  bucket = aws_s3_bucket.public.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadOnly"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.public.arn}/*"
        Condition = { Bool = { "aws:SecureTransport" = "true" } }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["${aws_s3_bucket.public.arn}", "${aws_s3_bucket.public.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

output "public_bucket_domain" {
  value = aws_s3_bucket.public.bucket_regional_domain_name
}
