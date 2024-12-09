provider "aws" {
  region  = "us-east-1"
  profile = "account-b"
  alias   = "account-b"
}

data "aws_iam_openid_connect_provider" "account_a_eks_oidc" {
  arn = module.eks.oidc_provider_arn
}

resource "aws_iam_openid_connect_provider" "account_b_oidc" {
  provider = aws.account-b

  url             = "https://${data.aws_iam_openid_connect_provider.account_a_eks_oidc.url}"
  client_id_list  = data.aws_iam_openid_connect_provider.account_a_eks_oidc.client_id_list
  thumbprint_list = data.aws_iam_openid_connect_provider.account_a_eks_oidc.thumbprint_list
}

resource "aws_iam_role" "cross_account_role" {
  provider           = aws.account-b
  name               = "bedrock-access-role"
  assume_role_policy = data.aws_iam_policy_document.trusted_entities.json
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  provider   = aws.account-b
  role       = aws_iam_role.cross_account_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_policy" "bedrock_invoke" {
  provider = aws.account-b
  name     = "bedrock-invoke"
  policy   = data.aws_iam_policy_document.bedrock_invoke.json
}

resource "aws_iam_role_policy_attachment" "bedrock_invoke" {
  provider   = aws.account-b
  role       = aws_iam_role.cross_account_role.name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

data "aws_iam_policy_document" "trusted_entities" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.account_b_oidc.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${aws_iam_openid_connect_provider.account_b_oidc.url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    actions   = ["bedrock:InvokeModel"]
    resources = ["*"]
    effect    = "Allow"
  }
}

output "cross_account_access_role_arn" {
  value = aws_iam_role.cross_account_role.arn
}
