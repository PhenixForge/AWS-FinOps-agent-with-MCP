# Read-only IAM role for the FinOps MCP tools, assumed by Bedrock AgentCore Runtime.
# Scope: Cost Explorer + CloudWatch, plus EC2 describe to identify GPU instances.
# No write/mutating action is granted on any AWS API.

resource "aws_iam_role" "finops_agent_readonly" {
  name = "finops-agent-readonly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # TODO: confirm the exact AgentCore Runtime service principal against AWS docs
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })

  tags = {
    project = "finops-mcp-agent-weekend"
  }
}

resource "aws_iam_role_policy" "finops_agent_readonly" {
  name = "finops-readonly"
  role  = aws_iam_role.finops_agent_readonly.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CostExplorerReadOnly"
        Effect   = "Allow"
        Action   = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "ce:GetDimensionValues",
          "ce:GetTags",
        ]
        Resource = "*"
      },
      {
        Sid      = "CloudWatchReadOnly"
        Effect   = "Allow"
        Action   = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
        ]
        Resource = "*"
      },
      {
        Sid      = "EC2DescribeOnly"
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
        ]
        Resource = "*"
      },
    ]
  })
}
