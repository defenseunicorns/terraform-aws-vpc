# Required vars
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

# To be handled with context
variable "name" {
  description = "Name to be used on all resources as identifier"
  type        = string
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

# To be handled with IL flag
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

# Optional
variable "permissions_boundary" {
  description = "ARN of a permissions boundary policy to use when creating IAM roles"
  type        = string
  default     = null
}

variable "secondary_cidr_blocks" {
  description = "List of secondary CIDR blocks for the VPC"
  type        = list(string)
  default     = []
}