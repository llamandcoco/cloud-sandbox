# -----------------------------------------------------------------------------
# Chatbot EventBridge - Platform
# cloud-sandbox/aws/10-plt/chatbot-eventbridge/terragrunt.hcl
#
# EventBridge event bus and rules for routing chatbot commands
# Routes commands to appropriate SQS queues for worker processing
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
  source = "github.com/llamandcoco/infra-modules//terraform/eventbridge?ref=${include.env.locals.eventbridge_ref}"
}

dependency "sr_sqs" {
  config_path = "../chatbot-command-sr-sqs"
  mock_outputs = {
    queue_arn = "arn:aws:sqs:ca-central-1:123456789012:mock-queue"
    dlq_arn   = "arn:aws:sqs:ca-central-1:123456789012:mock-queue-dlq"
  }
}

dependency "lw_sqs" {
  config_path = "../chatbot-command-lw-sqs"
  mock_outputs = {
    queue_arn = "arn:aws:sqs:ca-central-1:123456789012:mock-queue"
    dlq_arn   = "arn:aws:sqs:ca-central-1:123456789012:mock-queue-dlq"
  }
}

dependency "lr_sqs" {
  config_path = "../chatbot-command-lr-sqs"
  mock_outputs = {
    queue_arn = "arn:aws:sqs:ca-central-1:123456789012:mock-queue"
    dlq_arn   = "arn:aws:sqs:ca-central-1:123456789012:mock-queue-dlq"
  }
}

dependency "sw_sqs" {
  config_path = "../chatbot-command-sw-sqs"
  mock_outputs = {
    queue_arn = "arn:aws:sqs:ca-central-1:123456789012:mock-queue"
    dlq_arn   = "arn:aws:sqs:ca-central-1:123456789012:mock-queue-dlq"
  }
}

locals {
  org_prefix           = include.root.locals.org_prefix
  environment          = include.env.locals.environment
  event_bus_name       = "${local.org_prefix}-${local.environment}-chatbot"
  short_read_commands  = ["/echo", "/status"]
  short_write_commands = ["/scale", "/restart"]
  long_read_commands   = ["/analyze", "/report"]
  long_write_commands  = ["/build", "/deploy"]
  implemented_commands = concat(
    local.short_read_commands,
    local.short_write_commands,
    local.long_read_commands,
    local.long_write_commands
  )
}

inputs = {
  # Event bus configuration
  event_bus_name   = local.event_bus_name
  create_event_bus = true

  # Multiple rules configuration
  rules = [
    # Short-read command rule - routes to SR (short-read) queue
    {
      name        = "${local.org_prefix}-${local.environment}-chatbot-sr-command"
      description = "Routes short-read commands to short-read worker queue"
      enabled     = true

      # Event pattern - match echo commands
      event_pattern = jsonencode({
        source      = ["slack.command"]
        detail-type = ["Slack Command"]
        detail = {
          command = local.short_read_commands
        }
      })

      # Targets: SR (Short-Read) SQS Queue
      targets = [
        {
          target_id  = "sr-sqs"
          arn        = dependency.sr_sqs.outputs.queue_arn
          input_path = "$.detail" # Pass only the detail portion

          # DLQ for failed events
          dead_letter_config = {
            arn = dependency.sr_sqs.outputs.dlq_arn
          }

          # Retry policy
          retry_policy = {
            maximum_event_age_in_seconds = 3600 # 1 hour
            maximum_retry_attempts       = 3
          }
        }
      ]
    },

    # Short-write command rule - routes to SW worker queue
    {
      name        = "${local.org_prefix}-${local.environment}-chatbot-sw-command"
      description = "Routes short-write commands to short-write worker queue"
      enabled     = true

      event_pattern = jsonencode({
        source      = ["slack.command"]
        detail-type = ["Slack Command"]
        detail = {
          command = local.short_write_commands
        }
      })

      targets = [
        {
          target_id  = "sw-sqs"
          arn        = dependency.sw_sqs.outputs.queue_arn
          input_path = "$.detail"

          dead_letter_config = {
            arn = dependency.sw_sqs.outputs.dlq_arn
          }

          retry_policy = {
            maximum_event_age_in_seconds = 3600
            maximum_retry_attempts       = 3
          }
        }
      ]
    },

    # Long-read command rule - routes to LR worker queue
    {
      name        = "${local.org_prefix}-${local.environment}-chatbot-lr-command"
      description = "Routes long-read commands to long-read worker queue"
      enabled     = true

      event_pattern = jsonencode({
        source      = ["slack.command"]
        detail-type = ["Slack Command"]
        detail = {
          command = local.long_read_commands
        }
      })

      targets = [
        {
          target_id  = "lr-sqs"
          arn        = dependency.lr_sqs.outputs.queue_arn
          input_path = "$.detail"

          dead_letter_config = {
            arn = dependency.lr_sqs.outputs.dlq_arn
          }

          retry_policy = {
            maximum_event_age_in_seconds = 3600
            maximum_retry_attempts       = 3
          }
        }
      ]
    },

    # Long-write command rule - routes to LW (long-write) queue
    {
      name        = "${local.org_prefix}-${local.environment}-chatbot-lw-command"
      description = "Routes long-write commands to long-write worker queue (triggers GitHub Actions)"
      enabled     = true

      event_pattern = jsonencode({
        source      = ["slack.command"]
        detail-type = ["Slack Command"]
        detail = {
          command = local.long_write_commands
        }
      })

      targets = [
        {
          target_id  = "lw-sqs"
          arn        = dependency.lw_sqs.outputs.queue_arn
          input_path = "$.detail"

          dead_letter_config = {
            arn = dependency.lw_sqs.outputs.dlq_arn
          }

          retry_policy = {
            maximum_event_age_in_seconds = 3600
            maximum_retry_attempts       = 3
          }
        }
      ]
    },

    # Catch-all rule for undefined intents (not errors)
    # Treats unmatched commands as undefined intents rather than failures
    # Enables future extensions: help messages, intent inference, LLM normalization
    {
      name        = "${local.org_prefix}-${local.environment}-chatbot-catch-all"
      description = "Routes unmatched commands to short-read queue for graceful handling"
      enabled     = true

      event_pattern = jsonencode({
        source      = ["slack.command"]
        detail-type = ["Slack Command"]
        detail = {
          command = [{
            # Exclude all currently implemented commands
            # This list must be kept in sync with all command-specific rules above
            "anything-but" = local.implemented_commands
          }]
        }
      })

      targets = [
        {
          target_id  = "catch-all-sqs"
          arn        = dependency.sr_sqs.outputs.queue_arn
          input_path = "$.detail"
        }
      ]
    }
  ]

  # Archive for audit/debugging
  archive_config = {
    name           = "${local.event_bus_name}-archive"
    description    = "Archive of all chatbot events for 7 days"
    retention_days = 7

    event_pattern = jsonencode({
      source = ["slack.command"]
    })
  }

  # IAM role for EventBridge to invoke SQS targets
  create_role = true

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "slack-bot"
      Component   = "eventbridge"
    }
  )
}
