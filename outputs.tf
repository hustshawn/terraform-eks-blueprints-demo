output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

# output "karpenter_addon" {
#   value = module.eks_blueprints_addons.karpenter
# }
output "karpenter_node_iam_role_arn" {
  value = module.eks_blueprints_addons.karpenter.node_iam_role_arn
}
output "karpenter_node_profile_name" {
  value = module.eks_blueprints_addons.karpenter.node_instance_profile_name
}

# output "eks_module" {
#   value = module.eks
# }

# output "fargate_profile" {
#   value = module.eks.fargate_profiles
# }


output "cluster_primary_security_group_id" {
  value = module.eks.cluster_primary_security_group_id
}

output "cluster_additional_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "cluster_node_security_group_id" {
  value = module.eks.node_security_group_id
}

# output "efs_module" {
#   value = module.efs
# }
output "efs_volume_handle" {
  value = module.efs.id
}

output "efs_storage_class_name" {
  value = kubernetes_storage_class_v1.efs.id
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

# output "vpc" {
#   value = module.vpc
# }
