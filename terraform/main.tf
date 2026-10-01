provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

locals {
  name = "${var.project_name}-${var.environment}"

  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  availability_zone = var.availability_zone != "" ? var.availability_zone : data.aws_availability_zones.available.names[0]
}

module "networking" {
  source = "./modules/networking"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  availability_zone  = local.availability_zone
  tags               = local.tags
}

module "app" {
  source = "./modules/app"

  name               = local.name
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_id             = module.networking.vpc_id
  subnet_id          = module.networking.public_subnet_id
  allowed_http_cidrs = var.allowed_http_cidrs
  ssh_allowed_cidrs  = var.ssh_allowed_cidrs

  instance_type     = var.instance_type
  root_volume_size  = var.root_volume_size
  availability_zone = local.availability_zone

  http_port               = var.http_port
  container_port          = var.container_port
  image_tag               = var.image_tag
  deploy_interval_seconds = var.deploy_interval_seconds

  generate_ssh_key        = var.generate_ssh_key
  ssh_public_key          = var.ssh_public_key
  private_key_output_path = var.private_key_output_path

  ecr_image_tag_mutability = var.ecr_image_tag_mutability
  ecr_keep_last_images     = var.ecr_keep_last_images

  tags = local.tags
}