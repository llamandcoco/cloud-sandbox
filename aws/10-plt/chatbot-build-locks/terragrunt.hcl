# -----------------------------------------------------------------------------
# Chatbot Build Locks DynamoDB Table - Platform
# cloud-sandbox/aws/10-plt/chatbot-build-locks/terragrunt.hcl
#
# DynamoDB table for distributed locking of build/deploy operations
# Prevents duplicate builds when multiple users trigger the same command
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
  source = "github.com/llamandcoco/infra-modules//terraform/dynamodb?ref=${include.env.locals.dynamodb_ref}"
}

locals {
  org_prefix  = include.root.locals.org_prefix
  environment = include.env.locals.environment
  table_name  = "${local.org_prefix}-${local.environment}-chatbot-build-locks"
}

inputs = {
  # Table identification
  table_name = local.table_name

  # Partition key - lock identifier (e.g., "build-router-plt", "deploy-api-prod")
  hash_key = "lockKey"

  # Attributes
  attributes = [
    {
      name = "lockKey"
      type = "S"
    }
  ]

  # No sort key needed for simple locks
  range_key = null

  # TTL configuration (automatic cleanup of expired locks)
  ttl_enabled        = true
  ttl_attribute_name = "ttl"

  # Billing mode - PAY_PER_REQUEST for unpredictable traffic
  billing_mode = "PAY_PER_REQUEST"

  # Point-in-time recovery (disabled for sandbox/dev environments)
  point_in_time_recovery_enabled = false

  # Server-side encryption (AWS managed)
  server_side_encryption_enabled = true
  server_side_encryption_kms_key_arn = null  # Use AWS managed key

  # Global secondary indexes (none needed)
  global_secondary_indexes = []
  local_secondary_indexes  = []

  # Stream settings (not needed for locks)
  stream_enabled   = false
  stream_view_type = null

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "slack-bot"
      Component   = "build-locks"
      Purpose     = "distributed-locking"
      LockType    = "build-deploy"
    }
  )
}
