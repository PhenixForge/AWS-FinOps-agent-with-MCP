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

# Cognito-hosted domain: without it, the /oauth2/token endpoint used by the
# client_credentials flow (discovery_url below) doesn't exist, so no MCP
# client can ever obtain a token. Prefix must be globally unique across all
# AWS accounts under amazoncognito.com, hence the account ID suffix.
resource "aws_cognito_user_pool_domain" "finops_gateway" {
  domain       = "finops-gateway-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.finops_gateway.id
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

# Everything a real MCP client (Claude Code CLI, claude.ai connector) needs
# to authenticate and connect, retrievable after `terraform apply` without
# digging through the AWS console.
output "gateway_url" {
  description = "MCP endpoint URL to configure in the client"
  value       = aws_bedrockagentcore_gateway.finops_gateway.gateway_url
}

output "cognito_token_url" {
  description = "OAuth2 token endpoint for the client_credentials flow"
  value       = "https://${aws_cognito_user_pool_domain.finops_gateway.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token"
}

output "cognito_client_id" {
  description = "Cognito app client ID (client_credentials flow)"
  value       = aws_cognito_user_pool_client.finops_gateway.id
}

output "cognito_client_secret" {
  description = "Cognito app client secret (client_credentials flow)"
  value       = aws_cognito_user_pool_client.finops_gateway.client_secret
  sensitive   = true
}

output "cognito_oauth_scope" {
  description = "OAuth scope to request when obtaining a token"
  value       = "${aws_cognito_resource_server.finops_gateway.identifier}/invoke"
}
