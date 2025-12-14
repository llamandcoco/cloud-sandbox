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
  environment = "plt/aws"
  provider    = "aws"
  team        = "platform"
  owner       = "llama"

  # Parameter Store path prefix for this environment
  parameter_prefix = "/${local.environment}"

  # Common tags for this environment
  common_tags = {
    Environment = local.environment
    Provider    = local.provider
    Team        = local.team
    Owner       = local.owner
  }

  # Reference to infra-modules commit SHA
  networking_stack_ref = "cf07bc63832108f576a3d3fca082980759c66da1"
}
