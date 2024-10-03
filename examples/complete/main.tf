resource "random_id" "default" {
  byte_length = 2
}

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

locals {
  # Add randomness to names to avoid collisions when multiple users are using this example
  vpc_name = "${var.name_prefix}-${lower(random_id.default.hex)}"
  tags = merge(
    var.tags,
    {
      RootTFModule = replace(basename(path.cwd), "_", "-") # tag names based on the directory name
      ManagedBy    = "Terraform"
      Repo         = "https://github.com/defenseunicorns/terraform-aws-vpc"
    }
  )

}


module "subnet_addrs" {
  source = "git::https://github.com/hashicorp/terraform-cidr-subnets?ref=v1.0.0"

  base_cidr_block = "10.200.0.0/16"

  # new_bits is added to the cidr of vpc_cidr to chunk the subnets up
  # public-a - 10.200.0.0/22 - 1,022 hosts
  # public-b - 10.200.4.0/22 - 1,022 hosts
  # public-c - 10.200.8.0/22 - 1,022 hosts
  # private-a - 10.200.12.0/22 - 1,022 hosts
  # private-b - 10.200.16.0/22 - 1,022 hosts
  # private-c - 10.200.20.0/22 - 1,022 hosts
  # database-a - 10.200.24.0/27 - 30 hosts
  # database-b - 10.200.24.32/27 - 30 hosts
  # database-c - 10.200.24.64/27 - 30 hosts
  networks = [
    {
      name     = "public-a"
      new_bits = 6
    },
    {
      name     = "public-b"
      new_bits = 6
    },
    {
      name     = "public-c"
      new_bits = 6
    },
    {
      name     = "private-a"
      new_bits = 6
    },
    {
      name     = "private-b"
      new_bits = 6
    },
    {
      name     = "private-c"
      new_bits = 6
    },
    {
      name     = "database-a"
      new_bits = 11
    },
    {
      name     = "database-b"
      new_bits = 11
    },
    {
      name     = "database-c"
      new_bits = 11
    },
  ]
}

locals {
  azs              = [for az_name in slice(data.aws_availability_zones.available.names, 0, min(length(data.aws_availability_zones.available.names), 3)) : az_name]
  public_subnets   = [for k, v in module.subnet_addrs.network_cidr_blocks : v if strcontains(k, "public")]
  private_subnets  = [for k, v in module.subnet_addrs.network_cidr_blocks : v if strcontains(k, "private")]
  database_subnets = [for k, v in module.subnet_addrs.network_cidr_blocks : v if strcontains(k, "database")]
}

module "vpc" {
  #checkov:skip=CKV_TF_1: using ref to a specific version
  source = "../.."

  name                  = local.vpc_name
  vpc_cidr              = "10.200.0.0/16"
  secondary_cidr_blocks = ["100.64.0.0/16"] # Used for optimizing IP address usage by pods in an EKS cluster. See https://aws.amazon.com/blogs/containers/optimize-ip-addresses-usage-by-pods-in-your-amazon-eks-cluster/
  azs                   = local.azs
  public_subnets        = local.public_subnets
  private_subnets       = local.private_subnets
  database_subnets      = local.database_subnets
  intra_subnets         = [for k, v in module.vpc.azs : cidrsubnet(element(module.vpc.vpc_secondary_cidr_blocks, 0), 5, k)]
  ip_offsets_per_subnet = var.ip_offsets_per_subnet # List of offsets for IP reservations in each subnet.
  single_nat_gateway    = true
  enable_nat_gateway    = true
  ecr_endpoint_policy   = data.aws_iam_policy_document.ecr.json
  private_subnet_tags = {
    # Needed if you are deploying EKS v1.14 or earlier to this VPC. Not needed for EKS v1.15+.
    "kubernetes.io/cluster/my-cluster" = "owned"
    # Needed if you are using EKS with the AWS Load Balancer Controller v2.1.1 or earlier. Not needed if you are using a version of the Load Balancer Controller later than v2.1.1.
    "kubernetes.io/cluster/my-cluster" = "shared"
    # Needed if you are deploying EKS and load balancers to private subnets.
    "kubernetes.io/role/internal-elb" = 1
  }
  public_subnet_tags = {
    # Needed if you are deploying EKS and load balancers to public subnets. Not needed if you are only using private subnets for the EKS cluster.
    "kubernetes.io/role/elb" = 1
  }
  intra_subnet_tags = {
    "foo" = "bar"
  }
  create_database_subnet_group      = true
  instance_tenancy                  = "default"
  create_default_vpc_endpoints      = true
  vpc_flow_log_permissions_boundary = var.permissions_boundary
  tags                              = local.tags
}
