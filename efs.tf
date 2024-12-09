#---------------------------------------------------------------
# EFS
#---------------------------------------------------------------
module "efs" {
  source  = "terraform-aws-modules/efs/aws"
  version = "~> 1.6"

  creation_token = local.name
  name           = local.name

  # Mount targets / security group
  mount_targets = {
    for k, v in zipmap(local.azs, module.vpc.private_subnets) : k => { subnet_id = v }
  }
  security_group_description = "${local.name} EFS security group"
  security_group_vpc_id      = module.vpc.vpc_id
  security_group_rules = {
    vpc = {
      # relying on the defaults provided for EFS/NFS (2049/TCP + ingress)
      description = "NFS ingress from VPC private subnets"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
    }
  }

  tags = local.tags
}

resource "kubernetes_storage_class_v1" "efs" {
  metadata {
    name = "efs"
  }

  storage_provisioner = "efs.csi.aws.com"
  parameters = {
    provisioningMode = "efs-ap" # Dynamic provisioning
    # fileSystemId     = module.efs.id
    directoryPerms = "700"
  }

  mount_options = [
    "iam"
  ]

  depends_on = [
    module.eks_blueprints_addons
  ]
}


#----------------------------------------------------------------
# EFS Persistent Volume for Dify only
#----------------------------------------------------------------
# resource "kubernetes_persistent_volume_v1" "efs_pv" {
#   metadata {
#     name = "efs-pv"
#   }
#   spec {
#     capacity = {
#       storage = "10Gi"
#     }
#     access_modes                     = ["ReadWriteMany"]
#     persistent_volume_reclaim_policy = "Retain"
#     storage_class_name               = kubernetes_storage_class_v1.efs.id
#     persistent_volume_source {
#       csi {
#         driver        = "efs.csi.aws.com"
#         volume_handle = module.efs.id
#       }
#     }
#   }
# }

# resource "kubernetes_persistent_volume_claim_v1" "efs_pvc" {
#   metadata {
#     name      = "efs-pvc"
#     namespace = "dify"
#   }
#   spec {
#     access_modes       = ["ReadWriteMany"]
#     storage_class_name = kubernetes_storage_class_v1.efs.id
#     resources {
#       requests = {
#         storage = "10Gi"
#       }
#     }
#     volume_name = kubernetes_persistent_volume_v1.efs_pv.id
#   }
# }
