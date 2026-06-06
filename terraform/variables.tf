variable "aws_region" {
  description = "AWS region for resource provisioning"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier used as a prefix for all resource names"
  type        = string
  default     = "infra-lab"
}

variable "environment" {
  description = "Deployment environment label (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
