terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # State lives in S3 (ADR-0011). Values come from backend.hcl, see backend.hcl.example.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "varanasi"
      env        = "staging"
      managed_by = "terraform"
    }
  }
}
