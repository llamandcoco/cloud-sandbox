# -----------------------------------------------------------------------------
# Chatbot Echo Worker - Platform
# cloud-sandbox/aws/10-plt/chatbot-echo-worker/terragrunt.hcl
#
# Lambda worker for processing echo commands from SQS
# Responds to Slack with "async <text>"
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
  config_path = "../chatbot-echo-sqs"
}

locals {
  org_prefix    = include.root.locals.org_prefix
  environment   = include.env.locals.environment
  command       = "echo"
  function_name = "${local.org_prefix}-${local.environment}-chatbot-${local.command}-worker"

  # Source configuration
  use_s3         = get_env("USE_S3_ARTIFACTS", "false") == "true"
  lambda_version = get_env("LAMBDA_VERSION", "latest")

  # S3 configuration
  s3_bucket = "${local.org_prefix}-${local.environment}-lambda-artifacts"
  s3_key    = "${local.environment}/${local.command}/builds/${local.lambda_version}.zip"

  # Local development path (use absolute path for terragrunt cache compatibility)
  local_source = abspath("${get_terragrunt_dir()}/../../../../cloud-apps/applications/chatops/slack-bot/dist/${local.command}-worker.zip")
}

inputs = {
  # Lambda configuration
  function_name = local.function_name
  description   = "Processes echo commands and responds to Slack asynchronously"

  # Runtime
  runtime = "nodejs20.x"
  handler = "workers/echo/index.handler"

  # Source configuration (S3 or local)
  filename          = local.use_s3 ? null : local.local_source
  source_code_hash  = local.use_s3 ? null : filebase64sha256(local.local_source)
  s3_bucket         = local.use_s3 ? local.s3_bucket : null
  s3_key            = local.use_s3 ? local.s3_key : null
  s3_object_version = local.use_s3 && get_env("S3_OBJECT_VERSION", "") != "" ? get_env("S3_OBJECT_VERSION", "") : null

  # Performance
  memory_size = 256
  timeout     = 10 # Optimized for fast reads (short-read quadrant)

  # Architecture
  architectures = ["arm64"] # Graviton2

  # Concurrency control
  reserved_concurrent_executions = 100 # High concurrency for read operations

  # Environment variables
  environment_variables = {
    ORG_PREFIX           = local.org_prefix
    ENVIRONMENT          = local.environment
    AWS_PARAMETER_PREFIX = "/${local.org_prefix}/${local.environment}"
    LOG_LEVEL            = "info"
    NODE_ENV             = "production"
  }

  # SQS Event Source Mapping
  event_source_mappings = [
    {
      event_source_arn = dependency.sqs.outputs.queue_arn

      # Batch settings
      batch_size                         = 1 # Process one message at a time
      maximum_batching_window_in_seconds = 0 # No batching delay

      # Error handling
      function_response_types = ["ReportBatchItemFailures"]

      # Scaling
      scaling_config = {
        maximum_concurrency = 100 # Match reserved_concurrent_executions
      }

      # Filtering (optional - process all messages)
      filter_criteria = null
    }
  ]

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
    # SQS permissions (receive/delete)
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
    # X-Ray tracing
    {
      effect = "Allow"
      actions = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ]
      resources = ["*"]
    }
  ]

  # VPC configuration
  vpc_config = null

  # Logging
  log_retention_days = 7

  # Observability - X-Ray tracing
  tracing_config = {
    mode = "Active" # Enable X-Ray distributed tracing
  }

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Application     = "slack-bot"
      Component       = "echo-worker"
      Command         = "echo"
      CommandCategory = "short-read"
      SLOTarget       = "p99-500ms"
    }
  )
}
