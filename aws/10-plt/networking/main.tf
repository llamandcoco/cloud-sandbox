terraform {
  required_version = ">= 1.0"
}

variable "parameter_prefix" {
  description = "SSM Parameter Store prefix for this environment (e.g. /plt)."
  type        = string
}

variable "environment" {
  description = "Environment identifier used for tagging."
  type        = string
}

# Read networking configuration from Parameter Store
data "aws_ssm_parameter" "networking" {
  name = "${var.parameter_prefix}/networking/config"
}

locals {
  # Decode the SSM parameter value (JSON config blob)
  config = nonsensitive(jsondecode(data.aws_ssm_parameter.networking.value))

  tags = merge(
    var.default_tags,
    {
      Environment = var.environment
      Workload    = "platform"
      Component   = "networking"
    }
  )
}

module "networking" {
  source = "github.com/llamandcoco/infra-modules//terraform/stack/networking?ref=bc95898"

  name        = local.config.name
  cidr_block  = local.config.cidr_block
  azs         = local.config.azs
  enable_ipv6 = try(local.config.enable_ipv6, false)

  # VPC settings
  enable_dns_support                   = try(local.config.enable_dns_support, true)
  enable_dns_hostnames                 = try(local.config.enable_dns_hostnames, true)
  enable_network_address_usage_metrics = try(local.config.enable_network_address_usage_metrics, false)
  instance_tenancy                     = try(local.config.instance_tenancy, "default")

  # Subnets
  database_subnet_cidrs   = try(local.config.database_subnet_cidrs, [])
  map_public_ip_on_launch = try(local.config.map_public_ip_on_launch, true)

  # NAT + routing
  nat_gateway_mode       = try(local.config.nat_gateway_mode, "none")
  database_route_via_nat = try(local.config.database_route_via_nat, false)

  # Security groups
  workload_security_group_ingress = try(local.config.workload_security_group_ingress, [])
  workload_security_group_egress  = try(local.config.workload_security_group_egress, [])

  tags = local.tags
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.networking.private_subnet_ids
}

output "database_subnet_ids" {
  description = "Database subnet IDs."
  value       = module.networking.database_subnet_ids
}
