terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Remote state (recommended). Create the bucket once, then run:
  #   terraform init -backend-config="bucket=my-tfstate" \
  #                          -backend-config="key=simple-cicd/terraform.tfstate" \
  #                          -backend-config="region=eu-central-1" \
  #                          -backend-config="dynamodb_table=my-tf-locks" \
  #                          -backend-config="encrypt=true"
  # backend "s3" {}
}