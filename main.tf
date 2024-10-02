terraform {
  required_providers {
    context = {
      source  = "registry.terraform.io/cloudposse/context"
      version = "~> 0.4.0"
    }
  }
}
data "context_config" "this" {}
data "context_label" "this" {}
data "context_tags" "this" {}




data "aws_region" "current" {} # TODO: is this a safe assumption? - offload to context provider/init

locals {

  tags = merge(
    var.tags,
    {
      GithubRepo = "terraform-aws-vpc"
      GithubOrg  = "defenseunicorns"
  })
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  #checkov:skip=CKV_TF_1: using ref to a specific version
  source  = "terraform-aws-modules/vpc/aws"
  version = "v5.13.0"

  name                  = var.name
  cidr                  = var.vpc_cidr
  secondary_cidr_blocks = var.secondary_cidr_blocks

  azs              = var.azs
  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets

  private_subnet_tags = var.private_subnet_tags
  public_subnet_tags  = var.public_subnet_tags

  # Manage so we can name
  manage_default_network_acl = true
  default_network_acl_tags   = { Name = "${var.name}-default" }

  manage_default_route_table = true
  default_route_table_tags   = { Name = "${var.name}-default" }

  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.name}-default" }

  one_nat_gateway_per_az = true

  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  enable_flow_log                                 = true
  flow_log_cloudwatch_log_group_retention_in_days = 365
  vpc_flow_log_permissions_boundary               = var.vpc_flow_log_permissions_boundary
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60

  tags = local.tags # TODO: context provider
}

################################################################################
# VPC Endpoints Module
################################################################################

# Only required for airgap where we control the env

module "vpc_endpoints" {
  #checkov:skip=CKV_TF_1: using ref to a specific version
  count  = var.create_default_vpc_endpoints ? 1 : 0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git//modules/vpc-endpoints?ref=v5.9.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [data.aws_security_group.default.id]

  endpoints = merge(
    {
      s3 = {
        service          = "s3"
        service_endpoint = "com.amazonaws.${data.aws_region.current.name}.s3"
        service_type     = "Gateway"
        tags             = { Name = "s3-vpc-endpoint" }
        route_table_ids  = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
      },
      dynamodb = {
        service            = "dynamodb"
        service_endpoint   = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
        service_type       = "Gateway"
        route_table_ids    = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
        security_group_ids = [aws_security_group.vpc_tls[0].id]
        tags               = { Name = "dynamodb-vpc-endpoint" }
      },
      ssm = {
        service             = "ssm"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ssm"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      ssmmessages = {
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
        service             = "ssmmessages"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      lambda = {
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.lambda"
        service             = "lambda"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      sts = {
        service             = "sts"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.sts"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      logs = {
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.logs"
        service             = "logs"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      ec2 = {
        service             = "ec2"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ec2"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      ec2messages = {
        service             = "ec2messages"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      ecr_api = {
        service             = "ecr.api"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
        policy              = var.ecr_endpoint_policy
      },
      ecr_dkr = {
        service             = "ecr.dkr"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
        policy              = var.ecr_endpoint_policy
      },
      kms = {
        service             = "kms"
        service_endpoint    = var.enable_fips_vpce ? "com.amazonaws.${data.aws_region.current.name}.kms-fips" : "com.amazonaws.${data.aws_region.current.name}.kms"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      autoscaling = {
        service             = "autoscaling"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.autoscaling"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      elasticloadbalancing = {
        service             = "elasticloadbalancing"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.elasticloadbalancing"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      efs = {
        service             = "elasticfilesystem"
        service_endpoint    = var.enable_fips_vpce ? "com.amazonaws.${data.aws_region.current.name}.elasticfilesystem-fips" : "com.amazonaws.${data.aws_region.current.name}.elasticfilesystem"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
        route_table_ids     = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
      },
      secretsmanager = {
        service             = "secretsmanager"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      }
    },
    var.enable_ses_vpce ? {
      email_smtp = {
        service             = "email-smtp"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.email-smtp"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_smtp[0].id]
      }
    } : {}
  )

  tags = merge(local.tags, {
    Endpoint = "true"
  })

  depends_on = [aws_ec2_subnet_cidr_reservation.this]
}

################################################################################
# Supporting Resources
################################################################################

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "vpc_tls" {
  #checkov:skip=CKV2_AWS_5: Secuirity group is being referenced by the VPC endpoint
  count = var.create_default_vpc_endpoints ? 1 : 0

  name        = "${var.name}-vpc_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = (concat([module.vpc.vpc_cidr_block], module.vpc.vpc_secondary_cidr_blocks))
  }

  egress {
    description = "HTTPS to Managed Services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "vpc_smtp" {
  #checkov:skip=CKV2_AWS_5: Secuirity group is being referenced by the VPC endpoint
  count = var.create_default_vpc_endpoints && var.enable_ses_vpce ? 1 : 0

  name        = "${var.name}-vpc_smtp"
  description = "Allow SMTP inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SMTP from VPC"
    from_port   = 587
    to_port     = 587
    protocol    = "tcp"
    cidr_blocks = (concat([module.vpc.vpc_cidr_block], module.vpc.vpc_secondary_cidr_blocks))
  }

  egress {
    description = "SMTP to Managed Services"
    from_port   = 587
    to_port     = 587
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}
