resource "aws_eks_cluster" "prod" {
  name = "prod"

  access_config {
    authentication_mode = "API"
  }

  role_arn = aws_iam_role.cluster.arn
  version  = "1.35"

  vpc_config {
    subnet_ids = concat(
      module.vpc.public_subnet_id,
      module.vpc.private_subnet_id
    )
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}

resource "aws_eks_addon" "cni" {
  cluster_name = aws_eks_cluster.prod.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.prod.name
  addon_name                  = "coredns"
  addon_version               = "v1.10.1-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "PRESERVE"
}


resource "aws_iam_role" "cluster" {
  name = "eks-cluster-prod"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}


resource "aws_eks_access_entry" "prod" {
  cluster_name      = aws_eks_cluster.prod.name
  principal_arn     = "arn:aws:iam::463884819678:user/terraform"
}

resource "aws_eks_access_policy_association" "prod" {
  cluster_name  = aws_eks_cluster.prod.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:aws:iam::463884819678:user/terraform"

  access_scope {
    type       = "cluster"
  }
  depends_on = [ aws_eks_access_entry.prod ]
}

