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
    network_mode = "PUBLIC"
    # Deliberately not "VPC": Cost Explorer has no VPC PrivateLink support, so
    # even from a private subnet this agent would need a NAT gateway just to
    # reach it — ~$32-35/mo, far above this project's few-euros budget, to
    # reach an API that's public either way. See finops-mcp-agent.md
    # ("Retour d'expérience") for the full reasoning.
  }
}

resource "aws_bedrockagentcore_agent_runtime_endpoint" "finops_agent_endpoint" {
  name             = "finops_agent_endpoint"
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.finops_agent_runtime.agent_runtime_id
  description      = "Endpoint for agent runtime communication"
}