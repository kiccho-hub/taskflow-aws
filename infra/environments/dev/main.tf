terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "AdministratorAccess-840854900854"
}

locals {
  common_tags = {
    Environment = "dev"
    Project     = "taskflow"
    ManagedBy   = "terrafrom"
  }
}
