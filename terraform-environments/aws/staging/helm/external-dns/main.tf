locals {
  aws_region       = "ap-southeast-3"
  environment_name = "staging"
  tags = {
    ops_env              = "${local.environment_name}"
    ops_managed_by       = "terraform",
    ops_source_repo      = "kubernetes-ops",
    ops_source_repo_path = "terraform-environments/aws/${local.environment_name}/helm/external-dns",
    ops_owners           = "devops",
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.90.1"
    }
    random = {
      source = "hashicorp/random"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.7.1"
    }
  }

  backend "remote" {
    # Update to your Terraform Cloud organization
    organization = "stormcloaks"

    workspaces {
      name = "kubernetes-ops-staging-helm-external-dns"
    }
  }
}

provider "aws" {
  region = local.aws_region
}

data "terraform_remote_state" "eks" {
  backend = "remote"
  config = {
    # Update to your Terraform Cloud organization
    organization = "stormcloaks"
    workspaces = {
      name = "kubernetes-ops-staging-20-eks"
    }
  }
}

data "terraform_remote_state" "route53_hosted_zone" {
  backend = "remote"
  config = {
    # Update to your Terraform Cloud organization
    organization = "stormcloaks"
    workspaces = {
      name = "kubernetes-ops-staging-5-route53-hostedzone"
    }
  }
}

#
# EKS authentication
# # https://registry.terraform.io/providers/hashicorp/helm/latest/docs#exec-plugins
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1"
      args        = ["eks", "get-token", "--cluster-name", "${local.environment_name}"]
      command     = "aws"
    }
  }
}

#
# Helm - external-dns
#
module "external-dns" {
  source = "github.com/ManagedKube/kubernetes-ops//terraform-modules/aws/helm/external-dns?ref=v2.0.92"

  aws_region                  = local.aws_region
  cluster_name                = local.environment_name
  # eks_cluster_id              = data.terraform_remote_state.eks.outputs.cluster_id
  eks_cluster_oidc_issuer_url = data.terraform_remote_state.eks.outputs.cluster_oidc_issuer_url
  route53_hosted_zones        = data.terraform_remote_state.route53_hosted_zone.outputs.zone_id
  helm_values_2               = file("${path.module}/values.yaml")

  depends_on = [
    data.terraform_remote_state.eks
  ]
}
