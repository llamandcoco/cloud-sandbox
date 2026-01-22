# -----------------------------------------------------------------------------
# Chatbot Short-Write (SW) Command Queue - Platform
# cloud-sandbox/aws/10-plt/chatbot-command-sw-sqs/terragrunt.hcl
#
# Unified SQS queue for short write commands (/scale, /restart, etc.)
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
  quadrant    = "sw"

  queue_name     = "${local.org_prefix}-${local.environment}-chatbot-command-${local.quadrant}-queue"
  dlq_name       = "${local.queue_name}-dlq"
  event_bus_name = "${local.org_prefix}-${local.environment}-chatbot"

  account_id = include.root.locals.account_id
  region     = include.root.locals.default_region

  queue_arn = "arn:aws:sqs:${local.region}:${local.account_id}:${local.queue_name}"
  dlq_arn   = "arn:aws:sqs:${local.region}:${local.account_id}:${local.dlq_name}"

  event_bus_arn = "arn:aws:events:${local.region}:${local.account_id}:event-bus/${local.event_bus_name}"
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/sqs?ref=${include.env.locals.sqs_ref}"
}

inputs = {
  queue_name = local.queue_name
  fifo_queue = false

  visibility_timeout_seconds = 45 # 45s = 20s Lambda timeout + 25s buffer
  message_retention_seconds  = 86400
  max_message_size           = 262144
  delay_seconds              = 0
  receive_wait_time_seconds  = 20

  create_dlq                     = true
  dlq_name                       = local.dlq_name
  max_receive_count              = 2
  dlq_message_retention_seconds  = 259200 # 3 days
  dlq_visibility_timeout_seconds = 30
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
      Component    = "command-sw-sqs"
      Quadrant     = "sw"
      QuadrantName = "short-write"
    }
  )
}
