# -----------------------------------------------------------------------------
# Slack Interactive Handler - Platform
# cloud-sandbox/aws/10-plt/slack-interactive-handler/terragrunt.hcl
#
# Handles Slack interactive button clicks for deployment approval workflow
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
  function_name = "${local.org_prefix}-${local.environment}-slack-interactive-handler"
  lambda_source = "../../../../cloud-apps/applications/chatops/slack-bot/dist/interactive"
}

inputs = {
  function_name = local.function_name
  description   = "Handles Slack interactive button clicks for deployment approval"

  runtime       = "nodejs20.x"
  handler       = "index.handler"
  source_path   = local.lambda_source
  memory_size   = 256
  timeout       = 10 # Slack requires response within 3 seconds, but we can use response_url for longer operations
  architectures = ["arm64"]

  environment_variables = {
    ORG_PREFIX           = local.org_prefix
    ENVIRONMENT          = local.environment
    AWS_PARAMETER_PREFIX = "/${local.org_prefix}/${local.environment}"
    LOG_LEVEL            = "info"
    NODE_ENV             = "production"
    DYNAMODB_TABLE_NAME  = dependency.dynamodb.outputs.table_name
    EVENTBRIDGE_BUS_NAME = "${local.org_prefix}-${local.environment}-chatbot"
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
        "dynamodb:GetItem",
        "dynamodb:UpdateItem"
      ]
      resources = [
        dependency.dynamodb.outputs.table_arn
      ]
    },
    {
      effect = "Allow"
      actions = [
        "events:PutEvents"
      ]
      resources = [
        "arn:aws:events:ca-central-1:${include.root.locals.account_id}:event-bus/${local.org_prefix}-${local.environment}-chatbot"
      ]
    }
  ]

  vpc_config         = null
  log_retention_days = 7

  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "eks-scheduler"
      Component   = "interactive-handler"
    }
  )
}
