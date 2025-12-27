# -----------------------------------------------------------------------------
# Slack Router Lambda - Platform
# cloud-sandbox/aws/10-plt/slack-router-lambda/terragrunt.hcl
#
# Lambda function for routing Slack commands to EventBridge
# Validates Slack signatures and responds within 3 seconds
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

dependency "eventbridge" {
  config_path = "../chatbot-eventbridge"
  mock_outputs = {
    event_bus_name = "laco-plt-chatbot"
    event_bus_arn  = "arn:aws:events:ca-central-1:123456789012:event-bus/laco-plt-chatbot"
  }
}

locals {
  org_prefix    = include.root.locals.org_prefix
  environment   = include.env.locals.environment
  function_name = "${local.org_prefix}-${local.environment}-slack-router"

  # Source configuration
  use_s3         = get_env("USE_S3_ARTIFACTS", "false") == "true"
  lambda_version = get_env("LAMBDA_VERSION", "latest")

  # S3 configuration
  s3_bucket = "${local.org_prefix}-${local.environment}-lambda-artifacts"
  s3_key    = "${local.environment}/router/builds/${local.lambda_version}.zip"

  # Local development path (absolute path to avoid cache directory issues)
  local_source = "${get_terragrunt_dir()}/../../../../cloud-apps/applications/chatops/slack-bot/dist/router.zip"
}

inputs = {
  # Lambda configuration
  function_name = local.function_name
  description   = "Routes Slack commands to EventBridge for async processing"

  # Runtime
  runtime = "nodejs20.x"
  handler = "router/index.handler"

  # Source configuration (S3 or local)
  filename          = local.use_s3 ? null : local.local_source
  source_code_hash  = local.use_s3 ? null : filebase64sha256(local.local_source)
  s3_bucket         = local.use_s3 ? local.s3_bucket : null
  s3_key            = local.use_s3 ? local.s3_key : null
  s3_object_version = local.use_s3 && get_env("S3_OBJECT_VERSION", "") != "" ? get_env("S3_OBJECT_VERSION", "") : null

  # Performance
  memory_size = 256
  timeout     = 3  # Slack requires response within 3 seconds

  # Architecture
  architectures = ["arm64"]  # Graviton2

  # Concurrency control
  reserved_concurrent_executions = -1  # -1 = unreserved (no limit for API endpoint)

  # Environment variables
  environment_variables = {
    ORG_PREFIX              = local.org_prefix
    ENVIRONMENT             = local.environment
    AWS_PARAMETER_PREFIX    = "/${local.org_prefix}/${local.environment}"
    EVENTBRIDGE_BUS_NAME    = dependency.eventbridge.outputs.event_bus_name
    LOG_LEVEL               = "info"
    NODE_ENV                = "production"
  }

  # No event source mappings (triggered by API Gateway)
  event_source_mappings = []

  # IAM permissions
  policy_statements = [
    # Read Slack secrets
    {
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      resources = [
        "arn:aws:ssm:ca-central-1:*:parameter/laco/plt/aws/secrets/slack/*"
      ]
    },
    # Publish to EventBridge
    {
      effect = "Allow"
      actions = [
        "events:PutEvents"
      ]
      resources = [
        dependency.eventbridge.outputs.event_bus_arn
      ]
    }
  ]

  # VPC configuration
  vpc_config = null

  # Logging
  log_retention_days = 7

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "slack-bot"
      Component   = "router-lambda"
      GitRepo     = "llamandcoco/cloud-apps"
    }
  )
}
