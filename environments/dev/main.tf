terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
  }
}

provider "aws" {
    region = "ap-southeast-1" 
}

data "aws_eks_cluster" "dev-cluster" {
  name = aws_eks_cluster.dev-cluster.name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.dev-cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.dev-cluster.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.dev-cluster.name]
      command     = "aws"
    }
  }
}


module "vpc" {
  source = "../../modules/vpc"
  cidr_block = var.cidr_block
  public_subnet = var.public_subnet
  private_subnet = var.private_subnet
  AZ = var.AZ
}