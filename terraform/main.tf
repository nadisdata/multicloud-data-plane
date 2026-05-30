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

# Central log bucket for access logging across the landing zone.
resource "aws_s3_bucket" "logs" {
  bucket = "${var.name_prefix}-access-logs"
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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
  source      = "./modules/public-access"
  name_prefix = var.name_prefix
}
