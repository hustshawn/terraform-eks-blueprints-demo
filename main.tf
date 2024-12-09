provider "aws" {
  region = local.region
}

# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}


provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# provider "helm" {
#   kubernetes {
#     host                   = module.eks.cluster_endpoint
#     cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
#     token                  = data.aws_eks_cluster_auth.this.token
#   }
# }

# provider "kubectl" {
#   apply_retry_count      = 5
#   host                   = module.eks.cluster_endpoint
#   cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
#   token                  = data.aws_eks_cluster_auth.this.token
#   load_config_file       = false
# }
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    # token                  = data.aws_eks_cluster_auth.this.token
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

locals {
  # name   = basename(path.cwd)
  name   = "ipv4-prefix-delegation"
  region = "ap-southeast-1"

  cluster_version = "1.31"
  additional_iam_policies = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]

  domain       = "shawnzh.people.aws.dev"
  acm_domain   = "*.${local.domain}"
  grafana_host = "grafana.${local.domain}"
  argocd_host  = "argocd.${local.domain}"

  vpc_cidr = "10.5.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

data "aws_acm_certificate" "issued" {
  domain   = local.acm_domain
  statuses = ["ISSUED"]
}

data "aws_route53_zone" "selected" {
  name = local.domain
  # private_zone = true
}

resource "aws_iam_policy" "additional" {
  name = "${local.name}-fargate-additional"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

################################################################################
# Cluster
################################################################################

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"
  # version = "~> 19.18"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true


  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  # Enable zonal shift
  cluster_zonal_shift_config = {
    enabled = true
  }

  # cluster_compute_config = {
  #   enabled    = true
  #   node_pools = ["general-purpose"]
  # }
  # EKS Addons
  cluster_addons = {
    # Specify the VPC CNI addon outside of the module as shown below
    # to ensure the addon is configured before compute resources are created
    # See README for further details
    vpc-cni = {
      # Specify the VPC CNI addon should be deployed before compute to ensure
      # the addon is configured before data plane compute resources are created
      # See README for further details
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
        enableNetworkPolicy : "true"
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          # ENABLE_POD_ENI           = "true"
        }
      })
    }
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"
        # Require platform version: https://docs.aws.amazon.com/eks/latest/userguide/coredns-autoscaling.html#coredns-autoscaling-prereqs
        # autoscaling = {
        #   enabled = true
        #   # minReplicas = 2
        #   # maxReplicas = 10
        # }
      })
      preserve    = true
      most_recent = true
      timeouts = {
        create = "25m"
        delete = "10m"
      }
    }
    kube-proxy = {
      most_recent = true
    }

    aws-mountpoint-s3-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.aws_mountpoint_s3_csi_driver.iam_role_arn
    }
  }

  authentication_mode = "API_AND_CONFIG_MAP"
  # access_entries = {
  #   # One access entry with a policy associated
  #   example = {
  #     kubernetes_groups = []
  #     principal_arn     = "arn:aws:iam::123456789012:role/something"

  #     policy_associations = {
  #       example = {
  #         policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  #         access_scope = {
  #           namespaces = ["default"]
  #           type       = "namespace"
  #         }
  #       }
  #     }
  #   }
  # }


  create_cluster_security_group = true
  create_node_security_group    = true

  eks_managed_node_group_defaults = {
    # cluster_version = "1.30"
    instance_types = ["m5.xlarge"]
    ami_type       = "BOTTLEROCKET_x86_64"
    platform       = "bottlerocket"
    iam_role_additional_policies = {
      for k, v in local.additional_iam_policies : k => v
    }
    # tags = {
    #   ExtraTag = "EKS managed node group complete example"
    # }
  }

  eks_managed_node_groups = {
    # blue-ng = {
    #   instance_types = ["m5.large"]
    #   # cluster_version = "1.28" # Kubernetes version. Defaults to EKS Cluster Kubernetes version
    #   min_size     = 0
    #   max_size     = 2
    #   desired_size = 1
    # }
    # green-ng = {
    #   instance_types  = ["m5.large"]
    #   cluster_version = "1.31" # Kubernetes version. Defaults to EKS Cluster Kubernetes version
    #   min_size        = 0
    #   max_size        = 2
    #   desired_size    = 1
    # }
  }
  #  EKS K8s API cluster needs to be able to talk with the EKS worker nodes with port 15017/TCP and 15012/TCP which is used by Istio
  #  Istio in order to create sidecar needs to be able to communicate with webhook and for that network passage to EKS is needed.
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    ingress_15017 = {
      description                   = "Cluster API - Istio Webhook namespace.sidecar-injector.istio.io"
      protocol                      = "TCP"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_15012 = {
      description                   = "Cluster API to nodes ports/protocols"
      protocol                      = "TCP"
      from_port                     = 15012
      to_port                       = 15012
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }


  fargate_profile_defaults = {
    iam_role_additional_policies = {
      additional = aws_iam_policy.additional.arn
    }
  }
  fargate_profiles = {
    # Providing compute for default namespace
    default = {
      name = "default"
      selectors = [
        {
          namespace = "fargate-*"
        }
      ]
    }
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
    }
    # coredns = {
    #   name = "coredns"
    #   selectors = [
    #     {
    #       namespace = "kube-system"
    #       labels = {
    #         k8s-app = "kube-dns"
    #       }
    #     }
    #   ]
    # }
  }

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    # "karpenter.sh/discovery" = local.name
  })

}

#---------------------------------------------------------------
# Disable default GP2 Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "disable_gp2" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks.eks_cluster_id]
}
#---------------------------------------------------------------
# GP3 Storage Class - Set as default
#---------------------------------------------------------------
resource "kubernetes_storage_class" "default_gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }

  depends_on = [kubernetes_annotations.disable_gp2]
}
