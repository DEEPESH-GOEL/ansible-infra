###############################################################################
# Consumer workspace: app_a
#
# Reads the shared_vpc workspace's state through Terraform's http backend,
# pointed at the Harness IaCM state endpoint, then builds a subnet inside the
# VPC it finds there.
#
# The `resolved_vpc_id` output is the actual test assertion: if it renders a
# real vpc-xxxx at plan time, the cross-workspace read worked.
###############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "Region for the subnet. Must match the shared VPC's region."
  type        = string
  default     = "us-east-1"
}

variable "app_key" {
  description = "Which key to look up in the shared workspace's output maps."
  type        = string
  default     = "app_a"
}

###############################################################################
# Coordinates of the producing workspace. All four are visible in the Harness
# URL when you open the shared_vpc workspace.
###############################################################################

variable "harness_account_id" {
  description = "Harness account identifier."
  type        = string
}

variable "harness_org_id" {
  description = "Org identifier holding the shared_vpc workspace."
  type        = string
}

variable "harness_project_id" {
  description = "Project identifier holding the shared_vpc workspace."
  type        = string
}

variable "shared_workspace_id" {
  description = "Identifier of the producing workspace."
  type        = string
  default     = "shared_vpc"
}

#variable "harness_pat" {
#  description = "Harness PAT with read access to the shared_vpc workspace state."
#  type        = string
#  sensitive   = true
#}

###############################################################################
# The cross-workspace read.
#
# `password` is supplied here rather than via TF_HTTP_PASSWORD on purpose.
# TF_HTTP_* is process-global, and this workspace's OWN state backend is also
# http -- setting the env var risks overriding the credential Harness injected
# for it. Passing it in config keeps the two reads independent.
#
# Tradeoff, and it is a real one: data source config is recorded in this
# workspace's state, so the PAT lands there in plaintext. Fine for a scoped
# test; not a pattern to promote to production.
###############################################################################

data "terraform_remote_state" "network" {
  backend = "http"

  config = {
    address  = "https://app.harness.io/gateway/iacm/api/orgs/${var.harness_org_id}/projects/${var.harness_project_id}/workspaces/${var.shared_workspace_id}/terraform-backend?accountIdentifier=${var.harness_account_id}"
    username = "harness"
    password = "pat.l7HREAyVTnyfUsfUtPZUow.6a8ac777966c5442af572926.wxerDDvpciBP8YNO3uVO"
  }
}

locals {
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_ids[var.app_key]
  vpc_cidr = data.terraform_remote_state.network.outputs.vpc_cidrs[var.app_key]
}

resource "aws_subnet" "app" {
  vpc_id     = local.vpc_id
  cidr_block = cidrsubnet(local.vpc_cidr, 8, 1)

  tags = {
    Name      = "${var.app_key}-subnet"
    ManagedBy = "harness-iacm"
    ReadFrom  = var.shared_workspace_id
  }
}

output "resolved_vpc_id" {
  description = "Proof the remote state read resolved. Renders at plan time."
  value       = local.vpc_id
}

output "subnet_id" {
  description = "Subnet built inside the shared VPC."
  value       = aws_subnet.app.id
}
