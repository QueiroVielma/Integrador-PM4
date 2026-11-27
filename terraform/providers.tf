terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # O state fica em um bucket S3 para a pipeline conseguir ler e gravar.
  # Bucket e key (pm04/<ambiente>/terraform.tfstate) sao passados no terraform init
  backend "s3" {
    region       = "us-east-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # Tags colocadas automaticamente em todos os recursos
  default_tags {
    tags = {
      Project     = "PM-04"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
