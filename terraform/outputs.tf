locals {
  ssm_image_tag_parameter = "/${var.project_name}/${var.environment}/image_tag"
}

output "app_url" {
  description = "Public URL of the running application."
  value       = "http://${module.app.public_ip}:${var.http_port}"
}

output "public_ip" {
  description = "Public IPv4 address of the application server."
  value       = module.app.public_ip
}

output "instance_id" {
  description = "ID of the application EC2 instance."
  value       = module.app.instance_id
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.networking.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = module.networking.public_subnet_id
}

output "ecr_repository_url" {
  description = "ECR repository URL the CI/CD pipeline pushes images to."
  value       = module.app.ecr_repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name."
  value       = module.app.ecr_repository_name
}

output "ecr_registry_id" {
  description = "ECR registry (AWS account) ID."
  value       = module.app.ecr_registry_id
}

output "ssm_image_tag_parameter" {
  description = "SSM parameter the pipeline writes the deployed image tag to."
  value       = local.ssm_image_tag_parameter
}

output "instance_profile_arn" {
  description = "Instance profile ARN attached to the server (ECR pull + SSM)."
  value       = module.app.instance_profile_arn
}

output "ssh_command" {
  description = "SSH command using the generated key. Empty string when SSH is disabled or the key is not written locally."
  value       = module.app.ssh_command
}

output "private_key_path" {
  description = "Local path of the generated private key, if one was written."
  value       = module.app.private_key_path
}