# -----------------------------------------------------------------------------
# Chatbot Response Cache DynamoDB Table - Platform
# cloud-sandbox/aws/10-plt/chatbot-response-cache/terragrunt.hcl
#
# DynamoDB table for caching read-only operation responses
# Reduces GitHub API calls and improves response times for status queries
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
  table_name  = "${local.org_prefix}-${local.environment}-chatbot-response-cache"
}

inputs = {
  # Table identification
  table_name = local.table_name

  # Partition key - cache identifier (e.g., "status-router-plt", "status-all")
  hash_key = "cacheKey"

  # Attributes
  attributes = [
    {
      name = "cacheKey"
      type = "S"
    }
  ]

  # No sort key needed for simple cache
  range_key = null

  # TTL configuration (automatic cleanup of expired cache entries)
  ttl_enabled        = true
  ttl_attribute_name = "ttl"

  # Billing mode - PAY_PER_REQUEST for variable read-heavy workload
  billing_mode = "PAY_PER_REQUEST"

  # Point-in-time recovery (disabled for cache data - can be regenerated)
  point_in_time_recovery_enabled = false

  # Server-side encryption (AWS managed)
  server_side_encryption_enabled     = true
  server_side_encryption_kms_key_arn = null # Use AWS managed key

  # Global secondary indexes (none needed)
  global_secondary_indexes = []
  local_secondary_indexes  = []

  # Stream settings (not needed for cache)
  stream_enabled   = false
  stream_view_type = null

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "slack-bot"
      Component   = "response-cache"
      Purpose     = "response-caching"
      CacheType   = "read-only-responses"
    }
  )
}
