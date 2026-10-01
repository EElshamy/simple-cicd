variable "name" {
  description = "Name prefix for application resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "aws_region" {
  description = "AWS region hosting the resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the instance in."
  type        = string
}

variable "subnet_id" {
  description = "Subnet to place the instance in."
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for the instance."
  type        = string
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to reach the application port."
  type        = list(string)
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH. Empty disables SSH."
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
}

variable "http_port" {
  description = "Host port published for the container."
  type        = number
}

variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
}

variable "image_tag" {
  description = "Container image tag deployed by Terraform."
  type        = string
}

variable "deploy_interval_seconds" {
  description = "How often the server polls SSM for a new image tag."
  type        = number
}

variable "generate_ssh_key" {
  description = "Generate an SSH key pair with Terraform."
  type        = bool
}

variable "ssh_public_key" {
  description = "Existing SSH public key used when generate_ssh_key is false."
  type        = string
  default     = ""
}

variable "private_key_output_path" {
  description = "Local path to write the generated private key to."
  type        = string
  default     = ""
}

variable "ecr_image_tag_mutability" {
  description = "ECR tag mutability."
  type        = string
}

variable "ecr_keep_last_images" {
  description = "How many images ECR keeps before expiring older ones."
  type        = number
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}