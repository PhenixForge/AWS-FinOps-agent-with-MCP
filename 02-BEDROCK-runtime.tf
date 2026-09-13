# AWS Bedrock AgentCore configuration
# Needs a Runtime + Gateway to be deployed in the same VPC as the Bedrock AgentCore. 
# The Runtime and Gateway can be deployed in a separate module or stack, but they must be in the same VPC.

# The runtime execution role is the read-only role from 00-IAM.tf
# (finops_agent_readonly) — no separate role here, just an extra policy
# attached to it for pulling the agent's own container image from ECR.
data "aws_iam_policy_document" "ecr_permissions" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    effect    = "Allow"
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    effect    = "Allow"
    resources = [aws_ecr_repository.finops_ecr_repository.arn]
  }
}

resource "aws_iam_role_policy" "finops_agent_ecr_pull" {
  role   = aws_iam_role.finops_agent_readonly.id
  policy = data.aws_iam_policy_document.ecr_permissions.json
}

resource "aws_bedrockagentcore_agent_runtime" "finops_agent_runtime" {
  agent_runtime_name = "finops_agent_runtime"
  role_arn           = aws_iam_role.finops_agent_readonly.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.finops_ecr_repository.repository_url}:latest"
    }
  }

  network_configuration {
    network_mode = "VPC"

    network_mode_config {
      subnets         = aws_subnet.private[*].id
      security_groups = [aws_security_group.finops_agent_runtime.id]
    }
  }
  # CAUTION: the private/isolated route tables in main.tf only have gateway
  # endpoints for S3 and DynamoDB — no NAT/IGW route and no interface
  # endpoints for ECR, STS, CloudWatch, or Bedrock. As configured, the runtime
  # likely can't pull its own image from ECR nor call any AWS API.
  # AWS Cost Explorer (ce:*) has no VPC PrivateLink support at all — it's only
  # reachable over the public internet, so this agent needs a NAT gateway (or
  # a public network mode) regardless of which interface endpoints get added.
}

resource "aws_bedrockagentcore_agent_runtime_endpoint" "finops_agent_endpoint" {
  name             = "finops_agent_endpoint"
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.finops_agent_runtime.agent_runtime_id
  description      = "Endpoint for agent runtime communication"
}