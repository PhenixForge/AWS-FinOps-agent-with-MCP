# Shared execution role for the Bedrock AgentCore Runtime and Gateway
# (both assume it as "bedrock-agentcore.amazonaws.com"). It does NOT hold the
# Cost Explorer/CloudWatch/EC2 read scope — those calls happen in the
# finops-tools Lambda (04-MCP.tf), which has its own dedicated role. This role
# only gets what the Runtime/Gateway themselves need: pulling the Runtime's
# container image from ECR (02-BEDROCK-runtime.tf) and invoking the Lambda
# target (04-MCP.tf).

resource "aws_iam_role" "finops_agent_readonly" {
  name = "finops-agent-readonly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # Confirmed: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-permissions.html
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })

  tags = {
    project = "finops-mcp-agent"
  }
}
