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
    network_mode = "PRIVATE"
    # TODO: PRIVATE mode likely requires a vpc_config block (subnet_ids,
    # security_group_ids) — no VPC/subnet resources exist yet in this repo.
    # Verify the exact schema with `terraform providers schema` against the
    # hashicorp/aws v6.64.0 docs before applying, and add the VPC resources
    # (probably a new 00-VPC.tf) if the provider requires them for this mode.
  }
}

resource "aws_bedrockagentcore_agent_runtime_endpoint" "finops_agent_endpoint" {
  name             = "finops-agent-endpoint"
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.finops_agent_runtime.agent_runtime_id
  description      = "Endpoint for agent runtime communication"
}