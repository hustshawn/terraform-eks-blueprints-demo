data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "aws_cli_s3" {
  name               = "aws-cli-s3-eks-pod-identity"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "aws_cli_s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.aws_cli_s3.name
}

resource "aws_eks_pod_identity_association" "aws_cli_s3" {
  cluster_name    = module.eks.cluster_name
  namespace       = "default"
  service_account = "aws-cli-sa"
  role_arn        = aws_iam_role.aws_cli_s3.arn
}
