# -----------------------------------------------------------------------------
# Environment Configuration - AWS Platform
# cloud-sandbox/aws/10-plt/_env_common.hcl
#
# This file defines common settings for the platform environment.
# It is included by layer-level terragrunt.hcl files.
# Note: This file does NOT include root.hcl (Terragrunt allows only one level)
# -----------------------------------------------------------------------------

locals {
  # Environment metadata
  environment = "plt"
  provider    = "aws"
  team        = "platform"
  owner       = "llama"

  # Parameter Store path prefix for this environment
  parameter_prefix = "/${local.environment}/${local.provider}"

  # Common tags for this environment
  common_tags = {
    Environment = local.environment
    Provider    = local.provider
    Team        = local.team
    Owner       = local.owner
  }

  # Reference to infra-modules commit SHA
  networking_stack_ref = "main"
  sqs_ref              = "main"
  lambda_ref           = "main"
  eventbridge_ref      = "main"
  api_gateway_ref      = "main"
  api_lambda_stack_ref = "main"
  s3_ref               = "main"
}
