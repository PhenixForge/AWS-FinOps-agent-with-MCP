"""Placeholder Lambda backing the 3 FinOps MCP tools.

Not implemented yet — this only exists so the Terraform wiring (Gateway ->
Lambda -> Cost Explorer/CloudWatch/EC2) can be deployed and tested end to end
before the real tool logic is written. The exact event shape the AgentCore
Gateway sends for an MCP "lambda" target has not been verified against AWS
docs yet; confirm it before relying on the field names below.
"""


def handler(event, context):
    tool_name = event.get("toolName") or event.get("tool_name") or "unknown"
    return {
        "error": f"Tool '{tool_name}' is not implemented yet (placeholder Lambda).",
    }
