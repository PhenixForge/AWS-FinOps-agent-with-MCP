# MCP server exposing the 3 FinOps tool functions to the agent:
#   - cost by service / period (AWS Cost Explorer)
#   - active GPU instances (CloudWatch / EC2)
#   - GPU utilization rate (CloudWatch)
# Registered as an MCP target on the Bedrock AgentCore Gateway defined in 01-BEDROCK.tf
# (Gateway MCP spec 2026-07-28). Must live in the same VPC as the Runtime/Gateway.
# Uses the read-only IAM role from 00-IAM.tf — no write permissions on billing/metrics.
