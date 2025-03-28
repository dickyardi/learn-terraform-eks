variable "repository" {
  default = "200625654012.dkr.ecr.ap-southeast-3.amazonaws.com/sample-repo"
}

variable "tag" {
  default = "sample-app6"
}

variable "namespace" {
  type        = string
  default     = "sample-app"
  description = "Namespace to deploy the image into"
}

variable "fullnameOverride" {
  type        = string
  default     = "sample-app"
  description = "Chart name"
}