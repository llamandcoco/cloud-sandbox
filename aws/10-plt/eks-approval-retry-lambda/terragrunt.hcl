# -----------------------------------------------------------------------------
# EKS Approval Retry Lambda - Platform
# cloud-sandbox/aws/10-plt/eks-approval-retry-lambda/terragrunt.hcl
#
# Checks pending approvals every 15 minutes and sends retry reminders
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
  source = "github.com/llamandcoco/infra-modules//terraform/lambda?ref=${include.env.locals.lambda_ref}"
}

dependency "dynamodb" {
  config_path = "../eks-deployment-state"
  mock_outputs = {
    table_name = "laco-plt-eks-deployment-requests"
    table_arn  = "arn:aws:dynamodb:ca-central-1:123456789012:table/mock-table"
  }
}

locals {
  org_prefix    = include.root.locals.org_prefix
  environment   = include.env.locals.environment
  function_name = "${local.org_prefix}-${local.environment}-eks-approval-retry"
  lambda_source = "../../../../cloud-apps/applications/chatops/slack-bot/dist/workers/approval-retry"
}

inputs = {
  function_name = local.function_name
  description   = "Checks pending approvals and sends retry reminders"

  runtime       = "nodejs20.x"
  handler       = "index.handler"
  source_path   = local.lambda_source
  memory_size   = 256
  timeout       = 60 # Process multiple pending requests
  architectures = ["arm64"]

  environment_variables = {
    ORG_PREFIX           = local.org_prefix
    ENVIRONMENT          = local.environment
    AWS_PARAMETER_PREFIX = "/${local.org_prefix}/${local.environment}"
    LOG_LEVEL            = "info"
    NODE_ENV             = "production"
    DYNAMODB_TABLE_NAME  = dependency.dynamodb.outputs.table_name
    SLACK_CHANNEL_ID     = "C06XXXXXXXXX" # Replace with actual channel ID
  }

  policy_statements = [
    {
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      resources = [
        "arn:aws:ssm:ca-central-1:${include.root.locals.account_id}:parameter/laco/plt/aws/secrets/slack/*"
      ]
    },
    {
      effect = "Allow"
      actions = [
        "dynamodb:Query",
        "dynamodb:UpdateItem"
      ]
      resources = [
        dependency.dynamodb.outputs.table_arn,
        "${dependency.dynamodb.outputs.table_arn}/index/*"
      ]
    }
  ]

  vpc_config         = null
  log_retention_days = 7

  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "eks-scheduler"
      Component   = "approval-retry"
    }
  )
}
