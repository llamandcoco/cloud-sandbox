# -----------------------------------------------------------------------------
# Chatbot Long-Read (LR) Unified Worker - Platform
# cloud-sandbox/aws/10-plt/chatbot-command-lr-worker/terragrunt.hcl
#
# Unified Lambda worker for processing long-running read commands
# Handles: /analyze, /report, and future long-read commands
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
  config_path = "../chatbot-command-lr-sqs"
}

locals {
  org_prefix    = include.root.locals.org_prefix
  environment   = include.env.locals.environment
  quadrant      = "lr"
  function_name = "${local.org_prefix}-${local.environment}-chatbot-command-${local.quadrant}-worker"

  use_s3         = get_env("USE_S3_ARTIFACTS", "false") == "true"
  lambda_version = get_env("LAMBDA_VERSION", "latest")

  s3_bucket = "${local.org_prefix}-${local.environment}-lambda-artifacts"
  s3_key    = "${local.environment}/${local.quadrant}/builds/${local.lambda_version}.zip"

  local_source = abspath("${get_terragrunt_dir()}/../../../../cloud-apps/applications/chatops/slack-bot/dist/${local.quadrant}-worker.zip")
}

inputs = {
  function_name = local.function_name
  description   = "Unified worker for all long-read commands (analyze, report, etc.)"

  runtime = "nodejs20.x"
  handler = "workers/lr/index.handler"

  filename          = local.use_s3 ? null : local.local_source
  source_code_hash  = local.use_s3 ? null : filebase64sha256(local.local_source)
  s3_bucket         = local.use_s3 ? local.s3_bucket : null
  s3_key            = local.use_s3 ? local.s3_key : null
  s3_object_version = local.use_s3 && get_env("S3_OBJECT_VERSION", "") != "" ? get_env("S3_OBJECT_VERSION", "") : null

  memory_size = 512
  timeout     = 45

  architectures = ["arm64"]

  reserved_concurrent_executions = 10

  environment_variables = {
    ORG_PREFIX           = local.org_prefix
    ENVIRONMENT          = local.environment
    AWS_PARAMETER_PREFIX = "/${local.org_prefix}/${local.environment}"
    LOG_LEVEL            = "info"
    NODE_ENV             = "production"
    QUADRANT             = local.quadrant
  }

  event_source_mappings = [
    {
      event_source_arn = dependency.sqs.outputs.queue_arn

      batch_size                         = 1
      maximum_batching_window_in_seconds = 0

      function_response_types = ["ReportBatchItemFailures"]

      scaling_config = {
        maximum_concurrency = 10
      }

      filter_criteria = null
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
        "arn:aws:ssm:ca-central-1:${include.root.locals.account_id}:parameter/laco/plt/aws/secrets/slack/*"
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
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ]
      resources = ["*"]
    }
  ]

  vpc_config = null

  log_retention_days = 7

  tracing_config = {
    mode = "Active"
  }

  tags = merge(
    include.env.locals.common_tags,
    {
      Application     = "slack-bot"
      Component       = "command-lr-worker"
      Quadrant        = "lr"
      QuadrantName    = "long-read"
      CommandCategory = "long-read"
      SLOTarget       = "p99-30s"
    }
  )
}
