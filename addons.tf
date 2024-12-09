################################################################################
# EKS addons
################################################################################
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # disable the Telemetry from AWS using CloudFormation
  observability_tag = null

  # We want to wait for the Fargate profiles to be deployed first
  create_delay_dependencies = [for prof in module.eks.fargate_profiles : prof.fargate_profile_arn]

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      configuration_values = jsonencode({
        "controller" : {
          "volumeModificationFeature" : {
            "enabled" : true
          }
        },
        "sidecars" : {
          "snapshotter" : {
            "forceEnable" : true
          }
        }
      })
    }
    # adot = {
    #   most_recent = true
    # }
    # aws-efs-csi-driver = {}
    eks-pod-identity-agent = {
      most_recent = true
    }
    # amazon-cloudwatch-observability = {
    #   most_recent              = false
    #   service_account_role_arn = module.cloudwatch_addon_irsa.iam_role_arn
    # configuration_values = jsonencode(
    #   {
    #     "containerLogs" : { "enabled" : false },
    #     "agent" : {
    #       "config" : {
    #         "logs" : {
    #           "metrics_collected" : {
    #             "emf" : {},
    #             "kubernetes" : {
    #               "enhanced_container_insights" : true,
    #               "accelerated_compute_metrics" : true
    #             }
    #           }
    #           "force_flush_interval" : 5
    #         }
    #       }
    #     }
    #   }
    # )
    # }
    # Marketplace addon
    # kubecost_kubecost = {
    #   most_recent = true
    # }

  }

  enable_aws_efs_csi_driver = true
  aws_efs_csi_driver = {
    force = true
  }
  enable_cluster_autoscaler = false

  enable_karpenter = true
  karpenter = {
    chart_version       = "1.0.5"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    max_history         = 5
    set = [
      {
        name  = "settings.featureGates.drift"
        value = true
      },
      {
        name  = "settings.featureGates.spotToSpotConsolidation"
        value = true
      }
    ]
  }
  karpenter_node = {
    create_instance_profile      = true
    iam_role_additional_policies = local.additional_iam_policies
  }
  # karpenter_enable_spot_termination = true

  enable_metrics_server        = true
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      templatefile("${path.module}/kubernetes/kube-prometheus-stack/values.override.yaml", {
        ingressClassName = "alb"
        grafana_host     = local.grafana_host
        acm_cert_arn     = data.aws_acm_certificate.issued.arn
      })
    ]
  }
  enable_cluster_proportional_autoscaler = false
  cluster_proportional_autoscaler = {
    timeout = "300"
    values = [templatefile("${path.module}/kubernetes/cluster-proportional-autoscaler/values.override.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }
  # enable_coredns_cluster_proportional_autoscaler = true  # not supported
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.9.2"
    # configuration_values = jsonencode({
    #   "vpcId" : module.vpc.vpc_id,
    #   "region" : local.region,
    #   "clusterName" : module.eks.cluster_name,
    #   "serviceAccount" : {
    #     "annotations" : {
    #       "eks.amazonaws.com/role-arn" : module.aws_load_balancer_controller_irsa.iam_role_arn
    #     }
    #   }
    # })
  }
  enable_external_dns = true
  # need the zone arns to create role
  external_dns_route53_zone_arns = [data.aws_route53_zone.selected.arn]
  enable_cert_manager            = true


  enable_ingress_nginx = true
  ingress_nginx = {
    values = [templatefile("${path.module}/kubernetes/ingress-nginx/custom-values.yaml", {
      ssl_cert_arn = data.aws_acm_certificate.issued.arn
    })]
  }

  enable_argocd = true
  argocd = {
    values = [templatefile("${path.module}/kubernetes/argocd/values.override.yaml", {
      hostname     = local.argocd_host
      acm_cert_arn = data.aws_acm_certificate.issued.arn
    })]
    # set_values = [
    set = [
      {
        name  = "server.extraArgs[0]"
        value = "--insecure"
      }
    ]
  }
  #  argocd_manage_add_ons = false # Indicates that ArgoCD is responsible for managing/deploying add-ons
  # argocd_applications = {
  #   addons = {
  #     path               = "chart"
  #     repo_url           = "https://github.com/hustshawn/eks-blueprints-add-ons.git"
  #     add_on_application = true
  #   }
  #   # workloads = {
  #   #   path               = "envs/dev"
  #   #   repo_url           = "https://github.com/aws-samples/eks-blueprints-workloads.git"
  #   #   add_on_application = false
  #   # }
  # }

  helm_releases = {
    # nvidia-device-plugin = {
    #   description      = "A Helm chart for NVIDIA Device Plugin"
    #   namespace        = "nvidia-device-plugin"
    #   create_namespace = true
    #   chart            = "nvidia-device-plugin"
    #   chart_version    = "0.14.0"
    #   repository       = "https://nvidia.github.io/k8s-device-plugin"
    #   values           = [file("${path.module}/kubernetes/nvidia-device-plugin/values.yaml")]
    # }
    prometheus-adapter = {
      description      = "A Helm chart for Prometheus Adapter"
      namespace        = "prometheus-adapter"
      create_namespace = true
      chart            = "prometheus-adapter"
      chart_version    = "4.10.0"
      repository       = "https://prometheus-community.github.io/helm-charts"
      values = [
        <<-EOT
        prometheus:
          url: "http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc"
          port: "9090"
        EOT
      ]
    }
  }

  tags = local.tags
}



module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "cloudwatch_addon_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-cwagent-"
  role_policy_arns = {
    xray_policy       = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
    cloudwatch_policy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "amazon-cloudwatch:cloudwatch-agent",
        "amazon-cloudwatch:amazon-cloudwatch-observability-controller-manager",
      ]
    }
  }

  tags = local.tags

}

module "aws_mountpoint_s3_csi_driver" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-cwagent-"
  role_policy_arns = {
    s3_full_access = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  }
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "kube-system:s3-csi-driver-sa"
      ]
    }
  }
  tags = local.tags
}
################################################################################
# Karpenter resources
################################################################################
resource "kubectl_manifest" "karpenter_ec2_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
      - alias: bottlerocket@latest
      metadataOptions:
        httpEndpoint: enabled
        httpProtocolIPv6: disabled
        httpPutResponseHopLimit: 2
        httpTokens: required
      role: ${module.eks_blueprints_addons.karpenter.node_iam_role_name}
      securityGroupSelectorTerms:
      - tags:
          Name: ${local.name}-node
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${local.name}
      tags:
        karpenter.sh/discovery: ${local.name}
  YAML
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      disruption:
        budgets:
        - nodes: 10%
        consolidateAfter: 0s
        consolidationPolicy: WhenEmptyOrUnderutilized
      limits:
        cpu: 1k
      template:
        spec:
          expireAfter: 72h0m0s
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c", "m", "r"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "topology.kubernetes.io/zone"
            operator: In
            values: ${jsonencode(local.azs)}
          - key: "kubernetes.io/arch"
            operator: In
            # values: ["arm64", "amd64"]
            values: ["amd64"]
          - key: "karpenter.sh/capacity-type" # If not included, the webhook for the AWS cloud provider will default to on-demand
            operator: In
            values: ["spot", "on-demand"]
  YAML
}

resource "kubectl_manifest" "karpenter_controller_security_group_policy" {
  yaml_body = <<-YAML
    apiVersion: vpcresources.k8s.aws/v1beta1
    kind: SecurityGroupPolicy
    metadata:
      name: karpenter-controller-sgp
      namespace: karpenter
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/name: karpenter
          eks.amazonaws.com/fargate-profile: karpenter
      securityGroups:
        groupIds:
        - ${module.eks.cluster_primary_security_group_id}
        - ${module.eks.node_security_group_id}
  YAML
}
