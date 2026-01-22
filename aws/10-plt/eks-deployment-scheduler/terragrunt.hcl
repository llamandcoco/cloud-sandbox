# -----------------------------------------------------------------------------
# EKS Deployment Scheduler - Platform
# cloud-sandbox/aws/10-plt/eks-deployment-scheduler/terragrunt.hcl
#
# EventBridge scheduled rules for EKS cluster creation/deletion
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

dependency "deploy_worker" {
  config_path = "../chatbot-deploy-worker"
  mock_outputs = {
    function_arn = "arn:aws:lambda:ca-central-1:123456789012:function:mock-function"
  }
}

dependency "retry_lambda" {
  config_path = "../eks-approval-retry-lambda"
  mock_outputs = {
    function_arn = "arn:aws:lambda:ca-central-1:123456789012:function:mock-function"
  }
}

locals {
  org_prefix     = include.root.locals.org_prefix
  environment    = include.env.locals.environment
  event_bus_name = "${local.org_prefix}-${local.environment}-chatbot"
}

inputs = {
  # Use existing event bus
  event_bus_name   = local.event_bus_name
  create_event_bus = false

  # Scheduled rules for EKS deployment
  rules = [
    # 9 AM EST (14:00 UTC) - Create EKS cluster
    {
      name                = "${local.org_prefix}-${local.environment}-eks-create-schedule"
      description         = "Daily EKS cluster creation at 9 AM EST"
      schedule_expression = "cron(0 14 * * ? *)" # 9 AM EST = 14:00 UTC
      enabled             = true

      targets = [{
        target_id = "deploy-worker"
        arn       = dependency.deploy_worker.outputs.function_arn
        input = jsonencode({
          deployment_type = "create_cluster"
          cluster_config = {
            cluster_name = "laco-plt-platform-eks"
            environment  = "plt"
            version      = "1.28"
            region       = "ca-central-1"
          }
        })

        retry_policy = {
          maximum_event_age_in_seconds = 3600
          maximum_retry_attempts       = 2
        }
      }]
    },

    # 6 PM EST (23:00 UTC) - Delete EKS cluster
    {
      name                = "${local.org_prefix}-${local.environment}-eks-delete-schedule"
      description         = "Daily EKS cluster deletion at 6 PM EST"
      schedule_expression = "cron(0 23 * * ? *)" # 6 PM EST = 23:00 UTC
      enabled             = true

      targets = [{
        target_id = "deploy-worker"
        arn       = dependency.deploy_worker.outputs.function_arn
        input = jsonencode({
          deployment_type = "delete_cluster"
          cluster_config = {
            cluster_name = "laco-plt-platform-eks"
            environment  = "plt"
            region       = "ca-central-1"
          }
        })

        retry_policy = {
          maximum_event_age_in_seconds = 3600
          maximum_retry_attempts       = 2
        }
      }]
    },

    # Every 15 minutes - Check pending approvals
    {
      name                = "${local.org_prefix}-${local.environment}-eks-retry-check"
      description         = "Check pending approvals every 15 minutes"
      schedule_expression = "rate(15 minutes)"
      enabled             = true

      targets = [{
        target_id = "approval-retry"
        arn       = dependency.retry_lambda.outputs.function_arn

        retry_policy = {
          maximum_event_age_in_seconds = 900 # 15 minutes
          maximum_retry_attempts       = 1
        }
      }]
    }
  ]

  # No archive needed for scheduled events
  archive_config = null

  # IAM role for EventBridge to invoke Lambda targets
  create_role = true

  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "eks-scheduler"
      Component   = "eventbridge-scheduler"
    }
  )
}
