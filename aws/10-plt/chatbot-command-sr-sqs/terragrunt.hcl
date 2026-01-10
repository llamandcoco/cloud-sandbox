# -----------------------------------------------------------------------------
# Chatbot Short-Read (SR) Command Queue - Platform
# cloud-sandbox/aws/10-plt/chatbot-command-sr/sqs/terragrunt.hcl
#
# Unified SQS queue for all short-read commands (echo, status, etc.)
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
  quadrant    = "sr"

  # Resource names
  queue_name       = "${local.org_prefix}-${local.environment}-${local.quadrant}-queue"
  dlq_name         = "${local.queue_name}-dlq"
  event_bus_name   = "${local.org_prefix}-${local.environment}-chatbot"

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
  visibility_timeout_seconds = 15     # Optimized for fast processing (10s timeout + 5s buffer)
  message_retention_seconds  = 43200  # 12 hours (short-read commands are not critical)
  max_message_size           = 262144 # 256 KB
  delay_seconds              = 0
  receive_wait_time_seconds  = 20 # Long polling

  # Dead Letter Queue
  create_dlq                     = true
  dlq_name                       = local.dlq_name
  max_receive_count              = 2 # Reduced retries for fast reads
  dlq_message_retention_seconds  = 259200 # 3 days
  dlq_visibility_timeout_seconds = 30
  dlq_delay_seconds              = 0

  # Queue Policy - Allow EventBridge to send messages
  # Allows all rules from the chatbot event bus
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
  # Allows all rules from the chatbot event bus
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
      Component    = "sr-queue"
      Quadrant     = "sr"
      QuadrantName = "short-read"
    }
  )
}
