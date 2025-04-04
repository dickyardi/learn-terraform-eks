locals {
  aws_region       = "ap-southeast-3"
  environment_name = "staging"
  tags = {
    ops_env              = "${local.environment_name}"
    ops_managed_by       = "terraform",
    ops_source_repo      = "kubernetes-ops",
    ops_source_repo_path = "terraform-environments/aws/${local.environment_name}/helm/sample-app",
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
      name = "kubernetes-ops-staging-sample-app"
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
      name = "kubernetes-ops-${local.environment_name}-20-eks"
    }
  }
}

data "terraform_remote_state" "route53_hosted_zone" {
  backend = "remote"
  config = {
    # Update to your Terraform Cloud organization
    organization = "stormcloaks"
    workspaces = {
      name = "kubernetes-ops-${local.environment_name}-5-route53-hostedzone"
    }
  }
}

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

data "aws_eks_cluster_auth" "main" {
  name = local.environment_name
}

provider "kubectl" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
  load_config_file       = false
}

# Helm values file templating
data "template_file" "helm_values" {
  template = file("${path.module}/helm_values.yaml")
  # Parameters you want to pass into the helm_values.yaml.tpl file to be templated
  vars = {
    fullnameOverride = "${var.namespace}"
    repository       = var.repository
    tag              = var.tag
  }
}
module "sample-app" {
  source = "./modules/helm_generic"
  # this is the helm repo add URL
  repository = "https://helm-charts.managedkube.com"
  # This is the helm repo add name
  # official_chart_name = "standard-application"
  official_chart_name = "./charts/standard-application"
  # This is what you want to name the chart when deploying
  user_chart_name = var.fullnameOverride
  # The helm chart version you want to use
  helm_version = "1.0.33"
  # The namespace you want to install the chart into - it will create the namespace if it doesnt exist
  namespace = var.namespace
  # The helm chart values file
  helm_values = data.template_file.helm_values.rendered
}