# MCP server exposing the 3 FinOps tool functions to the agent:
#   - cost_by_service_period (AWS Cost Explorer)
#   - active_gpu_instances (EC2)
#   - gpu_utilization_rate (CloudWatch)
# One Lambda implements all 3 tools; the Gateway target (03-BEDROCK-gateway.tf)
# routes MCP tool calls to it, dispatching on tool name inside the handler.

data "archive_file" "finops_tools_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/finops-tools"
  output_path = "${path.module}/build/finops-tools.zip"
}

resource "aws_iam_role" "finops_tools_lambda" {
  name = "finops-tools-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })

  tags = {
    project = "finops-mcp-agent"
  }
}

resource "aws_iam_role_policy_attachment" "finops_tools_lambda_logs" {
  role       = aws_iam_role.finops_tools_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "finops_tools_lambda_readonly" {
  name   = "finops-readonly"
  role   = aws_iam_role.finops_tools_lambda.id
  policy = data.aws_iam_policy_document.finops_readonly_apis.json
}

resource "aws_lambda_function" "finops_tools" {
  function_name = "finops-tools"
  role          = aws_iam_role.finops_tools_lambda.arn

  filename         = data.archive_file.finops_tools_lambda.output_path
  source_code_hash = data.archive_file.finops_tools_lambda.output_base64sha256

  handler = "handler.handler"
  runtime = "python3.13"
  timeout = 10
}

# The Gateway's own role (finops_agent_readonly, 00-IAM.tf) needs permission
# to invoke this specific Lambda.
resource "aws_iam_role_policy" "finops_agent_invoke_tools_lambda" {
  name = "finops-invoke-tools-lambda"
  role = aws_iam_role.finops_agent_readonly.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.finops_tools.arn
      },
    ]
  })
}

# Resource-based policy on the Lambda itself, allowing the Gateway to invoke
# it. Principal/condition not yet verified against AWS docs — confirm the
# exact requirement before relying on this for a real deployment.
resource "aws_lambda_permission" "finops_gateway_invoke" {
  statement_id  = "AllowBedrockAgentCoreGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_tools.function_name
  principal     = "bedrock-agentcore.amazonaws.com"
  source_arn    = aws_bedrockagentcore_gateway.finops_gateway.gateway_arn
}

resource "aws_bedrockagentcore_gateway_target" "finops_tools" {
  gateway_identifier = aws_bedrockagentcore_gateway.finops_gateway.gateway_id
  name               = "finops-tools"
  description        = "Cost Explorer / CloudWatch / EC2 read-only FinOps tools"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.finops_tools.arn

        tool_schema {
          inline_payload {
            name        = "cost_by_service_period"
            description = "Get AWS cost broken down by service for a date range, e.g. GPU instance spend over the last 7 days."

            input_schema {
              type = "object"

              property {
                name        = "start_date"
                type        = "string"
                description = "Start date, YYYY-MM-DD"
                required    = true
              }
              property {
                name        = "end_date"
                type        = "string"
                description = "End date, YYYY-MM-DD"
                required    = true
              }
              property {
                name        = "service"
                type        = "string"
                description = "Optional AWS service filter, e.g. 'Amazon Elastic Compute Cloud - Compute'"
                required    = false
              }
            }

            output_schema {
              type        = "object"
              description = "Cost amounts grouped by service for the requested period"
            }
          }

          inline_payload {
            name        = "active_gpu_instances"
            description = "List currently running EC2 instances that have a GPU."

            input_schema {
              type        = "object"
              description = "No parameters required"
            }

            output_schema {
              type        = "array"
              description = "List of running GPU instances (instance ID, type, launch time)"
            }
          }

          inline_payload {
            name        = "gpu_utilization_rate"
            description = "Get the GPU utilization rate (CloudWatch) for a given EC2 instance."

            input_schema {
              type = "object"

              property {
                name        = "instance_id"
                type        = "string"
                description = "EC2 instance ID, e.g. i-0123456789abcdef0"
                required    = true
              }
              property {
                name        = "period_hours"
                type        = "number"
                description = "How many hours of history to average over (default 24)"
                required    = false
              }
            }

            output_schema {
              type        = "object"
              description = "GPU utilization percentage over the requested period"
            }
          }
        }
      }
    }
  }
}
