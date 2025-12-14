# -----------------------------------------------------------------------------
# Networking Stack - Platform
# cloud-sandbox/aws/10-plt/networking/terragrunt.hcl
#
# Deploys the platform VPC using infra-modules/stack/networking.
# All configuration values are specified directly in this file.
# -----------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env_common.hcl")
  expose = true
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/stack/networking?ref=${include.env.locals.networking_stack_ref}"
}

# All networking configuration
inputs = {
  # Basic VPC settings
  name       = "laco-plt"
  cidr_block = "172.16.0.0/16"
  azs        = ["ca-central-1a", "ca-central-1b"]

  # IPv6 and DNS
  enable_ipv6          = false
  enable_dns_support   = true
  enable_dns_hostnames = true

  # VPC settings
  enable_network_address_usage_metrics = false
  instance_tenancy                     = "default"

  # Subnets
  database_subnet_cidrs   = []
  map_public_ip_on_launch = true

  # NAT Gateway
  nat_gateway_mode       = "none"
  database_route_via_nat = false

  # Security Groups - use module defaults
  workload_security_group_ingress = []
  workload_security_group_egress = []

  # Tags
  tags = merge(
    include.env.locals.common_tags,
    {
      Workload  = "platform"
      Component = "networking"
      Module    = "stack/networking"
      GitSha    = include.env.locals.networking_stack_ref
      GitRepo   = "llamandcoco/infra-modules"
    }
  )
}
