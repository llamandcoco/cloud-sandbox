# -----------------------------------------------------------------------------
# Slack API Gateway - Platform
# cloud-sandbox/aws/10-plt/slack-api-gateway/terragrunt.hcl
#
# HTTP API Gateway for Slack slash commands
# Routes POST /slack/commands to Router Lambda
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
  source = "github.com/llamandcoco/infra-modules//terraform/api-gateway?ref=${include.env.locals.api_gateway_ref}"
}

dependency "lambda" {
  config_path = "../slack-router-lambda"
  mock_outputs = {
    function_arn  = "arn:aws:lambda:ca-central-1:123456789012:function:laco-plt-slack-router"
    function_name = "laco-plt-slack-router"
    invoke_arn    = "arn:aws:apigateway:ca-central-1:lambda:path/2015-03-31/functions/arn:aws:lambda:ca-central-1:123456789012:function:laco-plt-slack-router/invocations"
  }
}

locals {
  org_prefix  = include.root.locals.org_prefix
  environment = include.env.locals.environment
  api_name    = "${local.org_prefix}-${local.environment}-slack-bot"
}

inputs = {
  # API Gateway REST API configuration
  api_name        = local.api_name
  api_description = "Slack bot slash command webhook endpoint"
  stage_name      = "prod"

  # Endpoint type
  endpoint_types = ["REGIONAL"] # Regional for lower latency in ca-central-1

  # Resources (URL paths)
  # Create single path for /slack/commands
  resources = {
    slack_commands = {
      path_part = "slack"
      parent_id = null # Under root, creates /slack
    }
  }

  # Methods and integrations
  methods = {
    post_slack_commands = {
      resource_key     = "slack_commands" # Reference to resource above
      http_method      = "POST"
      authorization    = "NONE"
      api_key_required = false

      # Lambda proxy integration
      integration_type        = "AWS_PROXY"
      integration_http_method = "POST"
      integration_uri         = dependency.lambda.outputs.invoke_arn
      timeout_milliseconds    = 3000 # Slack 3-second requirement
    }
  }

  # Deployment configuration
  deployment_triggers = {
    redeployment = timestamp() # Redeploy on every apply
  }

  # Stage settings
  stage_settings = {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
    logging_level          = "INFO"
    metrics_enabled        = true
  }

  # Lambda invoke permission
  create_lambda_permission = true
  lambda_function_name     = dependency.lambda.outputs.function_name

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Application = "slack-bot"
      Component   = "api-gateway"
      GitRepo     = "llamandcoco/cloud-apps"
    }
  )
}
