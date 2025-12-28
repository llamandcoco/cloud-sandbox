# -----------------------------------------------------------------------------
# S3 Lambda Artifacts Bucket - Platform
# cloud-sandbox/aws/10-plt/s3-lambda-artifacts/terragrunt.hcl
#
# S3 bucket for storing Lambda deployment artifacts
# Structure: s3://bucket/plt/{function}/builds/{version}.zip
# -----------------------------------------------------------------------------

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "env" {
  path   = find_in_parent_folders("_env_common.hcl")
  expose = true
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/s3?ref=${include.env.locals.s3_ref}"
}

locals {
  org_prefix  = include.root.locals.org_prefix
  environment = include.env.locals.environment
  bucket_name = "${local.org_prefix}-${local.environment}-lambda-artifacts"
}

inputs = {
  # Bucket configuration
  bucket_name = local.bucket_name

  # Enable versioning for artifact rollback
  versioning = true

  # Lifecycle rules
  lifecycle_rules = [
    {
      id      = "cleanup-old-builds"
      enabled = true
      prefix  = "" # Apply to all objects

      # Delete old objects after 90 days
      expiration_days = 90

      # Keep only last 30 days of non-current versions
      noncurrent_version_expiration_days = 30
    }
  ]

  # Server-side encryption
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
      bucket_key_enabled = true
    }
  }

  # Block public access
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Purpose     = "Lambda deployment artifacts"
      Application = "slack-bot"
    }
  )
}
