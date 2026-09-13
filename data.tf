# Shared data sources (not variables — no user input here, just AWS lookups).

data "aws_caller_identity" "current" {}

# Read-only scope shared by whichever role actually calls these AWS APIs
# (the finops-tools Lambda in 04-MCP.tf, invoked via the Gateway target).
data "aws_iam_policy_document" "finops_readonly_apis" {
  statement {
    sid       = "CostExplorerReadOnly"
    effect    = "Allow"
    actions   = ["ce:GetCostAndUsage", "ce:GetCostForecast", "ce:GetDimensionValues", "ce:GetTags"]
    resources = ["*"]
  }

  statement {
    sid       = "CloudWatchReadOnly"
    effect    = "Allow"
    actions   = ["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics"]
    resources = ["*"]
  }

  statement {
    sid       = "EC2DescribeOnly"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeInstanceTypes"]
    resources = ["*"]
  }
}
