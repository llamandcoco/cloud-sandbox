# -----------------------------------------------------------------------------
# Root Terragrunt Configuration
# cloud-sandbox/root.hcl
#
# Shared backend and provider configuration for sandbox infrastructure stacks.
# -----------------------------------------------------------------------------

locals {
  # AWS Account ID
  account_id = run_cmd("aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text")

  # Default region
  default_region = "ca-central-1"

  # Organization
  organization = "llamandcoco"
  org_prefix   = "laco"
}

# Remote state configuration
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "${local.org_prefix}-terraform-state-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.default_region
    encrypt        = true
    dynamodb_table = "${local.org_prefix}-terraform-locks-${local.account_id}"
    s3_bucket_tags = {
      Name      = "sandbox-terraform-state"
      ManagedBy = "terragrunt"
      Purpose   = "terraform-state"
    }

    dynamodb_table_tags = {
      Name      = "sandbox-terraform-locks"
      ManagedBy = "terragrunt"
      Purpose   = "terraform-locks"
    }
  }
}

# Generate AWS provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default     = {}
}
EOF
}

# Common inputs for all stacks
inputs = {
  aws_region = local.default_region

  default_tags = {
    ManagedBy    = "terragrunt"
    Repository   = "github.com/llamandcoco/cloud-sandbox"
    Organization = local.organization
    Project      = "playground"
  }
}
