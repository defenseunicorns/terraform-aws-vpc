# Required
variable "required_vpc_vars" {
  description = <<-EOD
  These values are required to be set for the module to function
  For vpc_subnets, see https://github.com/hashicorp/terraform-cidr-subnets
  EOD
  type = object({
    vpc_cidr    = string
    secondary_cidr_blocks = list(string)
    vpc_subnets = list(object({
      name     = string
      mew_bits = number
    }

    ))
  })
}

variable "context_provider_info" {
  type = object({
    name = string
    tags = map(string)
    public_subnet_tags = map(string)
    private_subnet_tags = map(string)
    instance_tenancy = string
  })
  validation {
    condition     = contains(["default", "dedicated"], var.context_provider_info.instance_tenancy)
    error_message = "Value must be either default or dedicated."
  }
}

# Optional

variable "optional_vpc_vars" {
  description = "This variable can be set to give flexability on the deployment"
  type = object({
    permissions_boundary = optional(string)
    vpc_exclude_availability_zones = optional(list(string))
  })
    default = {}

}

##############
# Depreciated#
##############
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "vpc_subnets" {
  description = "A list of subnet objects to do subnet math things on - see https://github.com/hashicorp/terraform-cidr-subnets"
  type        = list(map(any))
  default     = [{}]
}

variable "secondary_cidr_blocks" {
  description = "List of secondary CIDR blocks for the VPC"
  type        = list(string)
  default     = []
}

variable "name" {
  description = "Name to be used on all resources as identifier"
  type        = string
  default     = "asdf"
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Tags to apply to public subnets"
  type        = map(string)
  default     = {}
}

# TODO: handled with IL flag
variable "instance_tenancy" {
  description = <<-EOD
  Tenancy of instances launched into the VPC.
  Valid values are "default" or "dedicated".
  EKS does not support dedicated tenancy.
  EOD
  type        = string
  default     = "default"
  validation {
    condition     = contains(["default", "dedicated"], var.instance_tenancy)
    error_message = "Value must be either default or dedicated."
  }
}

variable "permissions_boundary" {
  description = "ARN of a permissions boundary policy to use when creating IAM roles"
  type        = string
  default     = null
}

variable "vpc_exclude_availability_zones" {
  description = "List of availability zones to be excluded for the VPC. This will filter the default ones that are fetched based on the region."
  type        = list(string)
  default     = []
}
