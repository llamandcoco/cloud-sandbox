# -----------------------------------------------------------------------------
# Chatbot Deploy Worker - Platform
# cloud-sandbox/aws/10-plt/chatbot-deploy-worker/terragrunt.hcl
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

dependency "sqs" {
  config_path = "../chatbot-deploy-sqs"
}

dependency "dynamodb" {
  config_path = "../eks-deployment-state"
  mock_outputs = {
    table_name = "laco-plt-eks-deployment-requests"
    table_arn  = "arn:aws:dynamodb:ca-central-1:123456789012:table/mock-table"
  }
}

locals {
  org_prefix        = include.root.locals.org_prefix
  environment       = include.env.locals.environment
  command           = "deploy"
  function_name     = "${local.org_prefix}-${local.environment}-chatbot-${local.command}-worker"
  lambda_source     = "../../../../cloud-apps/applications/chatops/slack-bot/dist/workers/deploy"
}

inputs = {
  function_name = local.function_name
  description   = "Handles deployment commands from Slack"

  runtime = "nodejs20.x"
  handler = "index.handler"
  source_path = local.lambda_source

  memory_size                    = 1024  # Deploy needs more memory
  timeout                        = 900   # 15 minutes (max)
  reserved_concurrent_executions = 2     # Limit concurrent deploys

  architectures = ["arm64"]

  environment_variables = {
    ORG_PREFIX           = local.org_prefix
    ENVIRONMENT          = local.environment
    AWS_PARAMETER_PREFIX = "/${local.org_prefix}/${local.environment}"
    LOG_LEVEL            = "info"
    NODE_ENV             = "production"
    DYNAMODB_TABLE_NAME  = dependency.dynamodb.outputs.table_name
    SLACK_CHANNEL_ID     = "C06XXXXXXXXX"  # Replace with actual channel ID
  }

  event_source_mappings = [
    {
      event_source_arn                   = dependency.sqs.outputs.queue_arn
      batch_size                         = 1
      maximum_batching_window_in_seconds = 0
      function_response_types            = ["ReportBatchItemFailures"]
      scaling_config = {
        maximum_concurrency = 2
      }
    }
  ]

  policy_statements = [
    {
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      resources = [
        "arn:aws:ssm:ca-central-1:${include.root.locals.account_id}:parameter/laco/plt/aws/secrets/*"
      ]
    },
    {
      effect = "Allow"
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility"
      ]
      resources = [
        dependency.sqs.outputs.queue_arn
      ]
    },
    {
      effect = "Allow"
      actions = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query"
      ]
      resources = [
        dependency.dynamodb.outputs.table_arn,
        "${dependency.dynamodb.outputs.table_arn}/index/*"
      ]
    }
  ]

  vpc_config         = null
  log_retention_days = 14  # Deploy logs kept longer

  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "slack-bot"
      Component   = "deploy-worker"
      Command     = "deploy"
    }
  )
}
