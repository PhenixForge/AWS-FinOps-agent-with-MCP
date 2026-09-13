resource "aws_ecr_repository" "finops_ecr_repository" {
  name = "finops-ecr-repository"
}

# Lab-only policy: grants this account push/pull AND delete/admin actions on the
# repository. Fine for a solo lab with nothing else in ECR, but for a persistent
# project this should be tightened to push/pull only, or dropped entirely — same-account
# access already works via IAM identity policies, this resource policy is only strictly
# needed for cross-account access.
data "aws_iam_policy_document" "finops_iam_policy" {
  statement {
    sid    = "finops policy"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:GetRepositoryPolicy",
      "ecr:ListImages",
      "ecr:DeleteRepository",
      "ecr:BatchDeleteImage",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy",
    ]
  }
}

resource "aws_ecr_repository_policy" "finops_ecr_repository_policy" {
  repository = aws_ecr_repository.finops_ecr_repository.name
  policy     = data.aws_iam_policy_document.finops_iam_policy.json
}