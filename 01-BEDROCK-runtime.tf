# AWS Bedrock AgentCore configuration
# Needs a Runtime + Gateway to be deployed in the same VPC as the Bedrock AgentCore. 
# The Runtime and Gateway can be deployed in a separate module or stack, but they must be in the same VPC.

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

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
    resources = [aws_ecr_repository.example.arn]
  }
}

resource "aws_iam_role" "example" {
  name               = "bedrock-agentcore-runtime-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "finops_agent_readonly_policy" {
  role   = aws_iam_role.example.id
  policy = data.aws_iam_policy_document.ecr_permissions.json
}

resource "aws_bedrockagentcore_agent_runtime" "finops_agent_runtime" {
  agent_runtime_name = "finops_agent_runtime"
  role_arn           = aws_iam_role.example.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.example.repository_url}:latest"
    }
  }

  network_configuration {
    network_mode = "PUBLIC"
  }
}

resource "aws_bedrockagentcore_agent_runtime_endpoint" "finops_agent_endpoint" {
  name             = "finops-agent-endpoint"
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.finops_agent_runtime.agent_runtime_id
  description      = "Endpoint for agent runtime communication"
}