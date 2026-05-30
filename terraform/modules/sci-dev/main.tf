# ---------------------------------------------------------------------------
# SCIENCE DEVELOPMENT AREA (FISMA-Moderate target)
# Isolated account/subscription for researchers. Gets governed, read-through
# access to the data plane via an explicit cross-account role — never the
# data-plane keys directly.
# ---------------------------------------------------------------------------

variable "name_prefix" {
  type = string
}

variable "data_plane_bucket_arn" {
  type        = string
  description = "ARN of the FISMA-High data-plane bucket to grant read-through access to."
}

variable "trusted_principal_arns" {
  type        = list(string)
  description = "Principals (e.g., science workspace roles) allowed to assume the read role."
}

# Read-only, governed access role. Scientists assume this; they never hold
# standing credentials to the high-side data.
resource "aws_iam_role" "sci_read" {
  name = "${var.name_prefix}-sci-readonly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.trusted_principal_arns }
      Action    = "sts:AssumeRole"
      # Enforce phishing-resistant MFA on the cross-boundary hop.
      Condition = {
        Bool            = { "aws:MultiFactorAuthPresent" = "true" }
        NumericLessThan = { "aws:MultiFactorAuthAge" = "3600" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "sci_read" {
  name = "${var.name_prefix}-sci-readonly"
  role = aws_iam_role.sci_read.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        var.data_plane_bucket_arn,
        "${var.data_plane_bucket_arn}/*"
      ]
    }]
  })
}

output "sci_read_role_arn" {
  value = aws_iam_role.sci_read.arn
}
