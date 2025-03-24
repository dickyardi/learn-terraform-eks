locals {
  aws_region         = "ap-southeast-3"
  environment_name   = "staging"
  tags = {
    ops_env              = "${local.environment_name}"
    ops_managed_by       = "terraform",
    ops_source_repo      = "kubernetes-ops",
    ops_source_repo_path = "terraform-environments/aws/${local.environment_name}/helm/cert-manager",
    ops_owners           = "devops",
  } 
  base_name                = "kube-prometheus-stack"
  k8s_service_account_name = "kube-prometheus-stack-grafana"
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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
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
      name = "kubernetes-ops-staging-helm-kube-prometheus-stack"
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

data "aws_eks_cluster_auth" "main" {
  name = local.environment_name
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

provider "kubectl" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
  load_config_file       = false
}

resource "helm_release" "helm_chart" {
  chart            = "kube-prometheus-stack"
  namespace        = var.namespace
  create_namespace = "true"
  name             = var.chart_name
  version          = var.helm_version
  verify           = var.verify
  repository       = "https://prometheus-community.github.io/helm-charts"

  values = [
    # templatefile("${path.module}/values.yaml", {
    templatefile("./values_local.yaml", {
      enable_grafana_aws_role = var.enable_iam_assumable_role_grafana
      aws_account_id          = var.aws_account_id
      role_name               = local.k8s_service_account_name
    }),
    var.helm_values,
  ]
}

############################
# An AWS assumable role for grafana
#
# Use case:
# * If you want to give Grafana IAM permission to query AWS Cloudwatch logs
#
############################
module "iam_assumable_role_grafana" {
  count                         = var.enable_iam_assumable_role_grafana ? 1 : 0
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "3.6.0"
  create_role                   = true
  role_name                     = local.k8s_service_account_name
  provider_url                  = replace(var.eks_cluster_oidc_issuer_url, "https://", "")
  role_policy_arns              = [aws_iam_policy.grafana[0].arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:${var.namespace}:${local.k8s_service_account_name}"]
  tags                          = var.tags
}

# Policy doc: https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/iam-policy-example.json
resource "aws_iam_policy" "grafana" {
  count       = var.enable_iam_assumable_role_grafana ? 1 : 0
  name_prefix = "${local.base_name}-${var.environment_name}"
  description = "${local.base_name} for ${var.environment_name}"
  policy      = var.aws_policy_grafana
  tags        = var.tags
}
