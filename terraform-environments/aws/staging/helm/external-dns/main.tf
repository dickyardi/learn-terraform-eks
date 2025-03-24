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
  helm_repository = "https://kubernetes-sigs.github.io/external-dns/"
  official_chart_name = "external-dns"
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

module "iam_assumable_role_admin" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "3.6.0"
  create_role                   = true
  role_name                     = "${local.official_chart_name}-${var.cluster_name}"
  provider_url                  = replace(var.eks_cluster_oidc_issuer_url, "https://", "")
  role_policy_arns              = [aws_iam_policy.iam_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:${var.k8s_namespace}:${local.official_chart_name}"]
}

resource "aws_iam_policy" "iam_policy" {
  name_prefix = "${local.official_chart_name}-${var.cluster_name}"
  description = "EKS ${local.official_chart_name} policy for cluster ${var.eks_cluster_id}"
  policy      = data.aws_iam_policy_document.iam_policy_document.json
}

# IAM Role policy doc: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md
data "aws_iam_policy_document" "iam_policy_document" {
  statement {
    sid    = "k8sExternalDNS"
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets",
    ]

    resources = ["arn:aws:route53:::hostedzone/${var.route53_hosted_zones}"]
  }

  statement {
    sid    = "k8sExternalDNS2"
    effect = "Allow"

    actions = [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
    ]

    resources = ["*"]
  }
}

data "aws_caller_identity" "current" {}

#
# Helm values
#
data "template_file" "helm_values" {
  template = file("${path.module}/helm_values.tpl.yaml")
  vars = {
    awsAccountID       = data.aws_caller_identity.current.account_id
    clusterName        = var.cluster_name
    serviceAccountName = local.official_chart_name
    chartName          = local.official_chart_name
  }
}

module "external-dns" {
  source = "github.com/ManagedKube/kubernetes-ops//terraform-modules/aws/helm/helm_generic?ref=v1.0.27"

  repository          = local.helm_repository
  official_chart_name = local.official_chart_name
  user_chart_name     = var.user_chart_name
  helm_version        = var.helm_chart_version
  namespace           = var.k8s_namespace
  helm_values         = data.template_file.helm_values.rendered
  helm_values_2       = var.helm_values_2

  depends_on = [
    module.iam_assumable_role_admin
  ]
}
