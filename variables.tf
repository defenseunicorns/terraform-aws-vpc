variable "name" {
  description = "Name to be used on all resources as identifier"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  validation {
    condition = can(cidrsubnet(var.vpc_cidr, 0, 0)) && tonumber(regex("[0-9]+$", var.vpc_cidr)) <= 24
    error_message = "The vpc_cidr must be a valid CIDR block with a subnet mask of /24 or larger (e.g., /24, /23, /22)."
  }  
}

variable "instance_tenancy" {
  description = <<-EOD
  Tenancy of instances launched into the VPC.
  Valid values are "default" or "dedicated".
  EKS does not support dedicated tenancy.
  EOD
  type        = string
  default     = "dedicated"
  validation {
    condition     = contains(["default", "dedicated"], var.instance_tenancy)
    error_message = "Value must be either default or dedicated."
  }
}

variable "vpc_flow_log_permissions_boundary" {
  description = "The ARN of the Permissions Boundary for the VPC Flow Log IAM Role"
  type        = string
  default     = null
}

variable "ip_reservation_list" {
  description = "List of IP's to reserve."
  type        = list(string)
  default     = []
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
