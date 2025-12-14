# -----------------------------------------------------------------------------
# Networking Stack - Platform
# cloud-sandbox/aws/10-plt/networking/terragrunt.hcl
#
# Deploys the platform VPC using infra-modules/stack/networking.
# Configuration values are read from AWS Systems Manager Parameter Store that
# is managed in cloud-control-plane/envs/aws/10-plt/03-networking.
# -----------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env_common.hcl")
  expose = true
}

terraform {
  source = "."
}

locals {
  environment      = "plt/aws"
  parameter_prefix = "/${local.environment}"
}

# Inputs passed through to Terraform variables
inputs = {
  parameter_prefix = local.parameter_prefix
  environment      = local.environment
}
