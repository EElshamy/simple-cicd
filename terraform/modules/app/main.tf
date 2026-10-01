# --------------------------------------------------------------------------
# Container registry
# --------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = "${var.name}-app"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Name = "${var.name}-ecr" })
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last ${var.ecr_keep_last_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_keep_last_images
          countUnit   = "images"
        }
        action = { type = "expire" }
      }
    ]
  })

  depends_on = [aws_ecr_repository.app]
}

# Single source of truth for the deployed image tag. CI/CD writes this parameter,
# the server reads it, so shipping a new version never mutates Terraform state.
resource "aws_ssm_parameter" "image_tag" {
  name  = "/${var.name}/image_tag"
  type  = "String"
  value = var.image_tag

  tags = merge(var.tags, { Name = "${var.name}-image-tag" })
}

# --------------------------------------------------------------------------
# Access
# --------------------------------------------------------------------------

locals {
  private_key_path = try(local_file.private_key[0].filename, "")
}

resource "tls_private_key" "generated" {
  count = var.generate_ssh_key ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  count = var.generate_ssh_key && var.private_key_output_path != "" ? 1 : 0

  filename        = var.private_key_output_path
  content         = tls_private_key.generated[0].private_key_pem
  file_permission = "0600"
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name}-key"
  public_key = var.generate_ssh_key ? tls_private_key.generated[0].public_key_openssh : var.ssh_public_key

  lifecycle {
    precondition {
      condition     = var.generate_ssh_key || var.ssh_public_key != ""
      error_message = "Set ssh_public_key when generate_ssh_key is false."
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-key" })
}

# --------------------------------------------------------------------------
# IAM for the server: pull from ECR, report to SSM
# --------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, { Name = "${var.name}-instance-role" })
}

resource "aws_iam_role_policy" "ecr_pull" {
  name = "${var.name}-ecr-pull"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.name}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogGroup"]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/${var.name}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.instance.name

  tags = merge(var.tags, { Name = "${var.name}-instance-profile" })
}

# --------------------------------------------------------------------------
# Network security
# --------------------------------------------------------------------------

resource "aws_security_group" "http" {
  name        = "${var.name}-http"
  description = "HTTP access to the application"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-http-sg" })
}

resource "aws_security_group" "ssh" {
  count = length(var.ssh_allowed_cidrs) > 0 ? 1 : 0

  name        = "${var.name}-ssh"
  description = "SSH access to the application server"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-ssh-sg" })
}

# --------------------------------------------------------------------------
# Server
# --------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  app_dir                 = "/opt/${var.name}"
  ecr_repository_url      = "${aws_ecr_repository.app.registry_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.app.name}"
  ssm_image_tag_parameter = "/${var.name}/image_tag"

  deploy_script = templatefile("${path.module}/templates/deploy.sh.tftpl", {
    app_name                = var.name
    app_dir                 = local.app_dir
    aws_region              = var.aws_region
    ssm_image_tag_parameter = local.ssm_image_tag_parameter
    default_image_tag       = var.image_tag
    ecr_repository_url      = local.ecr_repository_url
    http_port               = var.http_port
    container_port          = var.container_port
  })

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    app_name                = var.name
    environment             = var.environment
    app_dir                 = local.app_dir
    http_port               = var.http_port
    container_port          = var.container_port
    deploy_interval_seconds = var.deploy_interval_seconds
    deploy_script           = local.deploy_script
  })
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = concat([aws_security_group.http.id], aws_security_group.ssh[*].id)
  iam_instance_profile   = aws_iam_instance_profile.this.name

  key_name = aws_key_pair.this.key_name

  associate_public_ip_address = true

  user_data = local.user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, {
    Name = "${var.name}-server"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------

output "instance_id" {
  description = "ID of the application server."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Public IP address of the application server."
  value       = aws_instance.app.public_ip
}

output "private_key_path" {
  description = "Local path of the generated private key, when written to disk."
  value       = local.private_key_path
}

output "ssh_command" {
  description = "Ready-to-run SSH command, or an empty string when SSH is disabled."
  value = (
    length(var.ssh_allowed_cidrs) == 0
    ? ""
    : var.generate_ssh_key
    ? "ssh -i ${local.private_key_path} ubuntu@${aws_instance.app.public_ip}"
    : "ssh ubuntu@${aws_instance.app.public_ip}"
  )
}

output "ssm_instance_id" {
  description = "Instance ID in the format required by SSM Session Manager."
  value       = aws_instance.app.id
}

output "instance_profile_arn" {
  description = "ARN of the instance profile."
  value       = aws_iam_instance_profile.this.arn
}

output "ecr_repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  description = "ECR repository URL used to push images."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_registry_id" {
  description = "ECR registry ID (AWS account ID)."
  value       = aws_ecr_repository.app.registry_id
}

output "ssm_image_tag_parameter" {
  description = "SSM parameter holding the deployed image tag."
  value       = aws_ssm_parameter.image_tag.name
}