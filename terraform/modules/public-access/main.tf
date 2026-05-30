# ---------------------------------------------------------------------------
# PUBLIC ACCESS LAYER (NOAA Open Data Dissemination pattern)
# Read-only, curated open-data bucket. Datasets are promoted here by an
# explicit, logged, one-way workflow from the protected plane.
# ---------------------------------------------------------------------------

variable "name_prefix" {
  type = string
}

resource "aws_s3_bucket" "public" {
  bucket = "${var.name_prefix}-public-open-data"
}

# Public READ is intentional here (open data), but writes stay locked down
# and ACLs are disabled — publishing is done by the promotion pipeline only.
resource "aws_s3_bucket_public_access_block" "public" {
  bucket                  = aws_s3_bucket.public.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "public" {
  bucket = aws_s3_bucket.public.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "public_read" {
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
