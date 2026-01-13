# -----------------------------------------------------------------------------
# Chatbot Long-Read (LR) Command Queue - Platform
# cloud-sandbox/aws/10-plt/chatbot-command-lr-sqs/terragrunt.hcl
#
# Unified SQS queue for long-running read commands (/analyze, /report, etc.)
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
  quadrant    = "lr"

  # Resource names - keep naming consistent with existing queues
  queue_name     = "${local.org_prefix}-${local.environment}-chatbot-command-${local.quadrant}-queue"
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
  queue_name = local.queue_name
  fifo_queue = false

  visibility_timeout_seconds = 90     # Buffer for longer read operations (30s+) + retry buffer
  message_retention_seconds  = 172800 # 2 days retention for longer command life
  max_message_size           = 262144
  delay_seconds              = 0
  receive_wait_time_seconds  = 20

  create_dlq                     = true
  dlq_name                       = local.dlq_name
  max_receive_count              = 3
  dlq_message_retention_seconds  = 604800 # 7 days
  dlq_visibility_timeout_seconds = 60
  dlq_delay_seconds              = 0

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

  redrive_allow_policy = null

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

  kms_master_key_id = null

  tags = merge(
    include.env.locals.common_tags,
    {
      Application  = "slack-bot"
      Component    = "command-lr-sqs"
      Quadrant     = "lr"
      QuadrantName = "long-read"
    }
  )
}
