variable "aws-region" {
  type        = string  
  description = "Região da AWS"
  default     = "us-east-1"
}

terraform {
  required_version = ">= 1.3, <= 1.7.5"

  backend "s3" {
    bucket         = "techchallengestate-g27"
    key            = "terraform-hackathon-apigateway/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }

  required_providers {
    
    random = {
      version = "~> 3.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.65"
    }
  }
}

provider "aws" {
  region = var.aws-region
}

data "aws_lb" "k8s_lb" {
  name = "k8s-default-ingressb-e8dce83f4f" 
}

resource "aws_apigatewayv2_api" "hackathon-apigateway" {
  name          = "hackathon-apigateway"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.hackathon-apigateway.id

  name        = "lanchonete"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "http_proxy_integration_basic" {
  for_each = toset([
    "POST/doctors",
    "GET/doctors",
    "POST/appointments",
    "GET/appointments",
    "POST/patients",
    "GET/patients",
    "POST/patients/auth/login",
    "POST/doctors/auth/login"
  ])

  api_id             = aws_apigatewayv2_api.hackathon-apigateway.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${data.aws_lb.k8s_lb.dns_name}/${join("/", slice(split("/", each.key), 1, length(split("/", each.key))))}"
  integration_method = split("/", each.key)[0]
}

resource "aws_apigatewayv2_integration" "http_proxy_integration_dynamic" {
  for_each = toset([
    "PATCH/patients/{id}",
    "PATCH/appointments/{id}/approval-status",
  ])

  api_id             = aws_apigatewayv2_api.hackathon-apigateway.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${data.aws_lb.k8s_lb.dns_name}/${join("/", slice(split("/", each.key), 1, length(split("/", each.key))))}"
  integration_method = split("/", each.key)[0]
}

resource "aws_apigatewayv2_route" "api_routes_dynamic" {
  for_each  = aws_apigatewayv2_integration.http_proxy_integration_dynamic
  api_id    = aws_apigatewayv2_api.hackathon-apigateway.id

  route_key = "${each.value.integration_method} /${each.key}"
  target    = "integrations/${each.value.id}"
}

resource "aws_apigatewayv2_route" "api_routes_basic" {
  for_each  = aws_apigatewayv2_integration.http_proxy_integration_basic
  api_id    = aws_apigatewayv2_api.hackathon-apigateway.id
  route_key = "${each.value.integration_method} /${split("/", each.key)[1]}"
  target    = "integrations/${each.value.id}"
}


resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.hackathon-apigateway.name}"

  retention_in_days = 30
}

output "aws_apigatewayv2_api_endpoint" {
  value = aws_apigatewayv2_api.hackathon-apigateway.api_endpoint
}