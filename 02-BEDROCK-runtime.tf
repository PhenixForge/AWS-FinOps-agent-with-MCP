# AWS Bedrock AgentCore Runtime — OPTIONAL for this project's actual demo.
#
# The demo clients (Claude Code CLI, claude.ai remote MCP connector, see
# finops-mcp-agent.md) already run their own agent loop; they talk to the
# Gateway + Lambda MCP server directly (03-BEDROCK-gateway.tf, 04-MCP.tf) and
# never call this Runtime. It's kept here as a placeholder to test, later and
# separately, the more "classic" standalone-agent pattern: a container
# running its own agent loop against a Bedrock model, invocable over HTTP
# independently of any MCP-aware client (e.g. a non-Claude caller). Needs a
# Dockerfile + agent code before it does anything — not required to make the
# main FinOps MCP demo work.

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