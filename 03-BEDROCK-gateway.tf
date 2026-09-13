# Cognito User Pool backing the Gateway's CUSTOM_JWT authorizer (OAuth/OIDC).
# Needed for the claude.ai remote MCP connector use case (client_credentials
# flow: Claude Code CLI / claude.ai obtain a token, present it to the Gateway).
resource "aws_cognito_user_pool" "finops_gateway" {
  name = "finops-gateway-users"
}

resource "aws_cognito_resource_server" "finops_gateway" {
  identifier   = "finops-gateway"
  name         = "finops-gateway"
  user_pool_id = aws_cognito_user_pool.finops_gateway.id

  scope {
    scope_name        = "invoke"
    scope_description = "Invoke the FinOps MCP gateway"
  }
}

resource "aws_cognito_user_pool_client" "finops_gateway" {
  name         = "finops-gateway-client"
  user_pool_id = aws_cognito_user_pool.finops_gateway.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.finops_gateway.identifier}/invoke"]

  depends_on = [aws_cognito_resource_server.finops_gateway]
}

resource "aws_bedrockagentcore_gateway" "finops_gateway" {
  name     = "finops-gateway"
  role_arn = aws_iam_role.finops_agent_readonly.arn

  authorizer_type = "CUSTOM_JWT"

  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.finops_gateway.id}/.well-known/openid-configuration"
      allowed_clients = [aws_cognito_user_pool_client.finops_gateway.id]
    }
  }

  protocol_configuration {
    mcp {}
  }
}
