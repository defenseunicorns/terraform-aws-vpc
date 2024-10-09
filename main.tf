data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_iam_policy_document" "ecr" {
  # checkov:skip=CKV_AWS_283: This policy allows EKS to access the regional ecr via a private VPC endpoint.
  # checkov:skip=CKV_AWS_111: Cannot constrain down resources without knowing specific ECR Repo information.
  statement {
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:CreateRepository",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DeleteRepository",
      "ecr:TagResource",
      "ecr:describeRepo",
      "ecr:DescribeRepositories"
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = ["*"]
  }

  statement {
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpc"

      values = [module.vpc.vpc_id]
    }
  }
}

resource "random_id" "default" {
  byte_length = 2
}

locals {
  azs              = [for az_name in slice(data.aws_availability_zones.available.names, 0, min(length(data.aws_availability_zones.available.names), 3)) : az_name]
  vpc_name = "${var.name}-${lower(random_id.default.hex)}"

  tags = merge(
    var.tags,
    {
      GithubRepo = "terraform-aws-vpc"
      GithubOrg  = "terraform-aws-modules"
  })
}

locals {
  # Determine the subnet mask size for 3 equal largest available subnets.
  # Example: If VPC is /22, 3 x /24 subnets can be derived.
  private_subnets = [
    cidrsubnet(var.vpc_cidr, 2, 0),
    cidrsubnet(var.vpc_cidr, 2, 1),
    cidrsubnet(var.vpc_cidr, 2, 2),
  ]

  intra_subnets = [
    cidrsubnet(module.vpc.vpc_secondary_cidr_blocks[0], 2, 0),
    cidrsubnet(module.vpc.vpc_secondary_cidr_blocks[0], 2, 1),
    cidrsubnet(module.vpc.vpc_secondary_cidr_blocks[0], 2, 2),
  ]

  # Directly specify the last three /28 subnets based on the VPC CIDR range
  database_subnets = [
    cidrsubnet(var.vpc_cidr, 4, 13), # .208/28
    cidrsubnet(var.vpc_cidr, 4, 14), # .224/28
    cidrsubnet(var.vpc_cidr, 4, 15), # .240/28
  ]
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  #checkov:skip=CKV_TF_1: using ref to a specific version
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v5.9.0"

  name                  = var.name
  cidr                  = var.vpc_cidr
  secondary_cidr_blocks = ["100.64.0.0/16"] # Used for optimizing IP address usage by pods in an EKS cluster. See https://aws.amazon.com/blogs/containers/optimize-ip-addresses-usage-by-pods-in-your-amazon-eks-cluster/

  azs              = local.azs
  private_subnets  = local.private_subnets
  intra_subnets    = local.intra_subnets
  # database_subnets = local.database_subnets # we should account for these from an IP space perspective but have them created by the database module

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
  
  intra_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "eks.amazonaws.com/component"     = "pod-subnet"
    "eks.amazonaws.com/pod-network"   = "non-routable"
    "NetworkPurpose"  = "EKS Pods"
    "RouteTable"      = "None"
  }

  create_database_subnet_group = false
  instance_tenancy             = "default"

  # Manage so we can name
  manage_default_network_acl = true
  default_network_acl_tags   = { Name = "${var.name}-default" }

  manage_default_route_table = true
  default_route_table_tags   = { Name = "${var.name}-default" }

  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.name}-default" }

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = false
  single_nat_gateway = false

  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  enable_flow_log                                 = true
  flow_log_cloudwatch_log_group_retention_in_days = 90
  flow_log_log_format                             = null
  vpc_flow_log_permissions_boundary               = var.vpc_flow_log_permissions_boundary
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60

  tags = local.tags
}

locals {
  ips     = var.ip_reservation_list
  cidrs   = module.vpc.private_subnets_cidr_blocks
  subnets = module.vpc.private_subnets

  # Create a mapping from CIDR blocks to subnet IDs
  subnet_cidr_map = { for idx, cidr in local.cidrs : cidr => local.subnets[idx] }

  # Map IP addresses to subnet IDs using cidr_contains
  ip_to_subnet = [
    for ip in local.ips : {
      ip        = ip
      subnet_id = try(
        (
          [for cidr, subnet_id in local.subnet_cidr_map : subnet_id
            if cidr_contains(cidr, ip)
          ][0]
        ),
        null
      )
    }
    if can(
      (
        [for cidr in keys(local.subnet_cidr_map) : cidr
          if cidr_contains(cidr, ip)
        ][0]
      )
    )
  ]
}

resource "aws_ec2_subnet_cidr_reservation" "this" {
  for_each = {
    for ip_map in local.ip_to_subnet : ip_map.ip => ip_map
  }

  subnet_id        = each.value.subnet_id
  cidr_block       = "${each.value.ip}/32"
  description      = "Reserved IP address for special use"
  reservation_type = "prefix"
}

################################################################################
# VPC Endpoints Module
################################################################################

locals {
  ecr_endpoint_policy = var.ecr_endpoint_policy != null ? var.ecr_endpoint_policy : data.aws_iam_policy_document.ecr.json
}

module "vpc_endpoints" {
  #checkov:skip=CKV_TF_1: using ref to a specific version
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
        route_table_ids  = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids])
      },
      dynamodb = {
        service            = "dynamodb"
        service_endpoint   = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
        service_type       = "Gateway"
        route_table_ids    = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids])
        security_group_ids = [aws_security_group.vpc_tls.id]
        tags               = { Name = "dynamodb-vpc-endpoint" }
      },
      ssm = {
        service             = "ssm"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ssm"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      ssmmessages = {
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
        service             = "ssmmessages"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      lambda = {
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.lambda"
        service             = "lambda"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      sts = {
        service             = "sts"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.sts"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      logs = {
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.logs"
        service             = "logs"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      ec2 = {
        service             = "ec2"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ec2"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      ec2messages = {
        service             = "ec2messages"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      ecr_api = {
        service             = "ecr.api"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
        policy              = local.ecr_endpoint_policy
      },
      ecr_dkr = {
        service             = "ecr.dkr"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
        policy              = local.ecr_endpoint_policy
      },
      kms = {
        service             = "kms"
        service_endpoint    = var.enable_fips_vpce ? "com.amazonaws.${data.aws_region.current.name}.kms-fips" : "com.amazonaws.${data.aws_region.current.name}.kms"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      autoscaling = {
        service             = "autoscaling"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.autoscaling"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      elasticloadbalancing = {
        service             = "elasticloadbalancing"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.elasticloadbalancing"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      },
      efs = {
        service             = "elasticfilesystem"
        service_endpoint    = var.enable_fips_vpce ? "com.amazonaws.${data.aws_region.current.name}.elasticfilesystem-fips" : "com.amazonaws.${data.aws_region.current.name}.elasticfilesystem"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
        route_table_ids     = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids])
      },
      secretsmanager = {
        service             = "secretsmanager"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_tls.id]
      }
    },
    {
      email_smtp = {
        service             = "email-smtp"
        service_endpoint    = "com.amazonaws.${data.aws_region.current.name}.email-smtp"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_smtp.id]
      }
    }
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
