terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.79"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13"
    }
    # kubectl = {
    #   source  = "gavinbunney/kubectl"
    #   version = ">= 1.14"
    # }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.2"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }

  # ##  Used for end-to-end testing on project; update to suit your needs
  backend "s3" {
    bucket  = "tf-eks-remote-states"
    region  = "ap-southeast-1"
    key     = "e2e/ipv4-prefix-delegation/terraform.tfstate"
    profile = "account-a"
  }
}
