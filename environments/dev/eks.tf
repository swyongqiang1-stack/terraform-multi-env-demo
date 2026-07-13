resource "aws_eks_cluster" "dev-cluster" {
  name = "dev"

  access_config {
    authentication_mode = "API"
  }

  role_arn = aws_iam_role.cluster.arn
  version  = "1.35"

  vpc_config {
    subnet_ids = [
      module.vpc.public_subnet_id,
      module.vpc.private_subnet_id
    ]
  }
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy
  ]
}

resource "aws_iam_role" "cluster" {
  name = "eks-cluster-dev"
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


resource "aws_eks_access_entry" "admin" {
  cluster_name      = aws_eks_cluster.dev-cluster.name
  principal_arn     = "arn:aws:iam::463884819678:user/terraform"
  type              = "STANDARD"
}


resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.dev-cluster.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:aws:iam::463884819678:user/terraform"

  access_scope {
    type       = "cluster"
  }
}
