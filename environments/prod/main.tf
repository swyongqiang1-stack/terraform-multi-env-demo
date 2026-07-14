terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "aws" {
    region = "ap-southeast-1" # 新加坡区
}


data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.prod.name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.prod.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.prod.name]
      command     = "aws"
    }
  }
}


module "vpc" {
  source = "../../modules/vpc"
  
}