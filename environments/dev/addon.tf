resource "aws_eks_addon" "cni" {
  cluster_name = aws_eks_cluster.dev-cluster.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "dns" {
  cluster_name                = aws_eks_cluster.dev-cluster.name
  addon_name                  = "coredns"
  addon_version               = "v1.10.1-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "PRESERVE"
}


resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.dev-cluster.name
  addon_name                  = "kube-proxy"
}