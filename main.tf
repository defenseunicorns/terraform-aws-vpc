data "aws_region" "current" {}

locals {

  tags = merge(
    var.tags,
    {
      GithubRepo = "terraform-aws-vpc"
      GithubOrg  = "terraform-aws-modules"
  })
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  #checkov:skip=CKV_TF_1: using ref to a specific version
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v5.9.0"

  name                  = var.name
  cidr                  = var.vpc_cidr
  secondary_cidr_blocks = var.secondary_cidr_blocks

  azs              = var.azs
  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets
  database_subnets = var.database_subnets
  intra_subnets    = var.intra_subnets

  private_subnet_tags = var.private_subnet_tags
  public_subnet_tags  = var.public_subnet_tags
  intra_subnet_tags   = var.intra_subnet_tags

  create_database_subnet_group = var.create_database_subnet_group
  instance_tenancy             = var.instance_tenancy

  # Manage so we can name
  manage_default_network_acl = true
  default_network_acl_tags   = { Name = "${var.name}-default" }

  manage_default_route_table = true
  default_route_table_tags   = { Name = "${var.name}-default" }

  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.name}-default" }

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  enable_flow_log                                 = true
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_cloudwatch_log_group_retention_in_days
  flow_log_log_format                             = var.flow_log_log_format
  vpc_flow_log_permissions_boundary               = var.vpc_flow_log_permissions_boundary
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60

  tags = local.tags
}

locals {
  reserved_ips_per_subnet = var.ip_offsets_per_subnet != null ? [for idx, cidr in module.vpc.private_subnets_cidr_blocks : [for offset in var.ip_offsets_per_subnet[idx] : cidrhost(cidr, offset)]] : []

  flat_reserved_details = [for idx, ips in local.reserved_ips_per_subnet : { subnet_id = module.vpc.private_subnets[idx], ips = ips }]

  flattened_ips     = flatten([for item in local.flat_reserved_details : item.ips])
  flattened_subnets = flatten([for item in local.flat_reserved_details : [for ip in item.ips : item.subnet_id]])
}

resource "aws_ec2_subnet_cidr_reservation" "this" {
  count            = length(local.flattened_ips)
  subnet_id        = local.flattened_subnets[count.index]
  cidr_block       = format("%s/32", local.flattened_ips[count.index])
  description      = "Reserved IP block for special use"
  reservation_type = "prefix"
}

################################################################################
# VPC Endpoints Module
################################################################################

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
      },
      sqs = {
        service             = "sqs"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.sqs"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls[0].id]
      },
      monitoring = {
        service             = "monitoring"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.monitoring"
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
