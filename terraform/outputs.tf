#
# Outputs
#

locals {
  config_maps = <<CONFIGMAPS

apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.astounding-node.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis
  namespace: cam
data:
  redisHost: ${aws_elasticache_cluster.astounding-redis.cache_nodes.0.address}
  redisUrl: redis://${aws_elasticache_cluster.astounding-redis.cache_nodes.0.address}:6379/0

CONFIGMAPS

  kubeconfig = <<KUBECONFIG


apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.astounding.endpoint}
    certificate-authority-data: ${aws_eks_cluster.astounding.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${var.cluster-name}"
KUBECONFIG
}

output "config_maps" {
  value = local.config_maps
}

output "kubeconfig" {
  value = local.kubeconfig
}
