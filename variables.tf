# Required
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

# Context provider/init offload
variable "name" {
  description = "Name to be used on all resources as identifier"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "azs" {
  description = "List of availability zones to deploy into"
  type        = list(string)
}

variable "private_subnet_tags" {
  description = "Tags to apply to private subnets"
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Tags to apply to public subnets"
  type        = map(string)
  default     = {}
}

variable "public_subnets" {
  description = "List of public subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "private_subnets" {
  description = "List of private subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "secondary_cidr_blocks" {
  description = "List of secondary CIDR blocks for the VPC"
  type        = list(string)
  default     = []
}

variable "vpc_flow_log_permissions_boundary" {
  description = "The ARN of the Permissions Boundary for the VPC Flow Log IAM Role"
  type        = string
  default     = null
}

variable "create_default_vpc_endpoints" {
  description = "Creates a default set of VPC endpoints."
  type        = bool
  default     = false
}

variable "ecr_endpoint_policy" {
  description = "Policy to attach to the ECR endpoint. Defaults to *."
  type        = string
  default     = null
}

variable "enable_fips_vpce" {
  description = "Enable FIPS endpoints for VPC endpoints."
  type        = bool
  default     = false
}
variable "enable_ses_vpce" {
  description = "Enable Simple Email Service endpoints for the VPC endpoints."
  type        = bool
  default     = true
}
