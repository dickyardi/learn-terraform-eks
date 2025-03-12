locals {
  aws_region       = "ap-southeast-3"
  environment_name = "staging"
  tags = {
    ops_env              = "${local.environment_name}"
    ops_managed_by       = "terraform",
    ops_source_repo      = "kubernetes-ops",
    ops_source_repo_path = "terraform-environments/aws/${local.environment_name}/20-eks",
    ops_owners           = "devops",
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.90.1"
    }
    random = {
      source = "hashicorp/random"
    }
  }

  backend "remote" {
    # Update to your Terraform Cloud organization
    organization = "stormcloaks"

    workspaces {
      name = "kubernetes-ops-staging-20-eks"
    }
  }
}

provider "aws" {
  region = local.aws_region
}

data "terraform_remote_state" "vpc" {
  backend = "remote"
  config = {
    # Update to your Terraform Cloud organization
    organization = "stormcloaks"
    workspaces = {
      name = "kubernetes-ops-${local.environment_name}-10-vpc"
    }
  }
}

#
# EKS
#
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.34.0"

  tags       = local.tags

  cluster_name = local.environment_name

  vpc_id         = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids     = data.terraform_remote_state.vpc.outputs.public_subnets

  cluster_version = "1.31"

  # public cluster - kubernetes API is publicly accessible
  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = [
    "0.0.0.0/0",
    "1.1.1.1/32",
  ]

  # private cluster - kubernetes API is internal the the VPC
  cluster_endpoint_private_access                = true
  create_cluster_security_group                  = true

  # Add whatever roles and users you want to access your cluster
  kms_key_users = [
    "arn:aws:iam::200625654012:user/kube-admin"
  ]

  eks_managed_node_groups  = {
    ng1 = {
      version          = "1.31"
      ami_type         = "AL2023_x86_64_STANDARD"
      instance_types   = ["t3.small"]
      disk_size        = 20
      desired_size     = 2
      max_size         = 3
      min_size         = 1
      additional_tags  = local.tags
    }
  }
}
