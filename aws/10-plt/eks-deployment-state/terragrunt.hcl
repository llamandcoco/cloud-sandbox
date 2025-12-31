# -----------------------------------------------------------------------------
# EKS Deployment State - Platform
# cloud-sandbox/aws/10-plt/eks-deployment-state/terragrunt.hcl
#
# DynamoDB table for tracking EKS deployment requests and approval workflow
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
  org_prefix = include.root.locals.org_prefix
  environment = include.env.locals.environment
  table_name = "${local.org_prefix}-${local.environment}-eks-deployment-requests"
}

inputs = {
  table_name   = local.table_name
  billing_mode = "PAY_PER_REQUEST"  # On-demand for low traffic
  hash_key     = "request_id"
  range_key    = "created_at"

  attributes = [
    {
      name = "request_id"
      type = "S"
    },
    {
      name = "created_at"
      type = "S"
    },
    {
      name = "status"
      type = "S"
    },
    {
      name = "scheduled_time"
      type = "S"
    }
  ]

  global_secondary_indexes = [
    {
      name            = "status-scheduled_time-index"
      hash_key        = "status"
      range_key       = "scheduled_time"
      projection_type = "ALL"
    }
  ]

  ttl_enabled        = true
  ttl_attribute_name = "expires_at"

  point_in_time_recovery_enabled = true

  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "eks-scheduler"
      Component   = "state-management"
    }
  )
}
