variable "project_name" {
  description = "Name prefix applied to every resource created by this stack."
  type        = string
  default     = "simple-cicd"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 4-32 characters, lowercase alphanumeric or dashes, and start with a letter (it is used in resource names)."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet hosting the application server."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Optional AZ for the subnet. Defaults to the first AZ available in the region."
  type        = string
  default     = ""
}

# --------------------------------------------------------------------------
# Application server
# --------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for the application server."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to reach the application over HTTP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH. Leave empty to disable SSH entirely and use SSM Session Manager only."
  type        = list(string)
  default     = []
}

variable "http_port" {
  description = "Host port published for the container."
  type        = number
  default     = 80
}

variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
  default     = 3000
}

variable "image_tag" {
  description = "Initial container image tag to deploy. The CI/CD pipeline overrides this via SSM Parameter Store."
  type        = string
  default     = "latest"
}

variable "deploy_interval_seconds" {
  description = "How often the server polls SSM for a new image tag."
  type        = number
  default     = 60
}

# --------------------------------------------------------------------------
# SSH access
# --------------------------------------------------------------------------

variable "generate_ssh_key" {
  description = "Generate an SSH key pair with Terraform. Set false to use ssh_public_key instead."
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "Existing SSH public key. Required when generate_ssh_key is false."
  type        = string
  default     = ""
}

variable "private_key_output_path" {
  description = "Write the generated private key to this local path. Leave empty to skip writing it to disk."
  type        = string
  default     = ""
}

# --------------------------------------------------------------------------
# Container registry
# --------------------------------------------------------------------------

variable "ecr_image_tag_mutability" {
  description = "Whether ECR tags can be overwritten. Must be MUTABLE for tag-based deployments."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_keep_last_images" {
  description = "Number of most recent images to keep before ECR expires older ones."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Extra tags merged into the default tags on every resource."
  type        = map(string)
  default     = {}
}