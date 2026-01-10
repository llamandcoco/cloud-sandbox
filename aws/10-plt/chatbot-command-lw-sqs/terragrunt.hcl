# -----------------------------------------------------------------------------
# Chatbot Long-Write (LW) Command Queue - Platform
# cloud-sandbox/aws/10-plt/chatbot-command-lw-sqs/terragrunt.hcl
#
# Unified SQS queue for all long-write commands (build, deploy, etc.)
# -----------------------------------------------------------------------------

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "env" {
  path   = find_in_parent_folders("_env_common.hcl")
  expose = true
}

locals {
  org_prefix  = include.root.locals.org_prefix
  environment = include.env.locals.environment
  quadrant    = "lw"

  # Resource names
  queue_name     = "${local.org_prefix}-${local.environment}-${local.quadrant}-queue"
  dlq_name       = "${local.queue_name}-dlq"
  event_bus_name = "${local.org_prefix}-${local.environment}-chatbot"

  # AWS metadata
  account_id = include.root.locals.account_id
  region     = include.root.locals.default_region

  # Queue ARNs
  queue_arn = "arn:aws:sqs:${local.region}:${local.account_id}:${local.queue_name}"
  dlq_arn   = "arn:aws:sqs:${local.region}:${local.account_id}:${local.dlq_name}"

  # EventBridge ARN
  event_bus_arn = "arn:aws:events:${local.region}:${local.account_id}:event-bus/${local.event_bus_name}"
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/sqs?ref=${include.env.locals.sqs_ref}"
}

inputs = {
  # Queue identification
  queue_name = local.queue_name
  fifo_queue = false

  # Message configuration
  visibility_timeout_seconds = 180    # Extended for long operations (120s timeout + 60s buffer)
  message_retention_seconds  = 172800 # 2 days
  max_message_size           = 262144 # 256 KB
  delay_seconds              = 0      # No queue-level delay; rate limiting handled by Lambda concurrency
  receive_wait_time_seconds  = 20     # Long polling

  # Dead Letter Queue
  create_dlq                     = true
  dlq_name                       = local.dlq_name
  max_receive_count              = 1      # No retry for writes (fail fast)
  dlq_message_retention_seconds  = 604800 # 7 days
  dlq_visibility_timeout_seconds = 30
  dlq_delay_seconds              = 0

  # Queue Policy - Allow EventBridge to send messages
  queue_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowChatbotEventBridgeToSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = local.queue_arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:events:${local.region}:${local.account_id}:rule/${local.event_bus_name}/*"
          }
        }
      }
    ]
  })

  # Redrive Allow Policy - Not needed for main queue
  redrive_allow_policy = null

  # DLQ Policy - Allow EventBridge to send failed events to DLQ
  dlq_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowChatbotEventBridgeToSendMessageToDLQ"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = local.dlq_arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:events:${local.region}:${local.account_id}:rule/${local.event_bus_name}/*"
          }
        }
      }
    ]
  })

  # Encryption - SQS-managed
  kms_master_key_id = null

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Application  = "slack-bot"
      Component    = "lw-queue"
      Quadrant     = "lw"
      QuadrantName = "long-write"
    }
  )
}
