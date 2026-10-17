variable "region" {
  description = "Region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "pipeline-dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "flow_log_retention_days" {
  description = "How long to keep VPC flow logs."
  type        = number
  default     = 365
}
