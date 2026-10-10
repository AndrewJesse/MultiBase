terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {} # configured by scripts/bootstrap.sh via backend.hcl
}

provider "aws" {
  alias  = "a"
  region = var.region_a
  default_tags {
    tags = { Project = "multibase", Stack = "compute" }
  }
}

provider "aws" {
  alias  = "b"
  region = var.region_b
  default_tags {
    tags = { Project = "multibase", Stack = "compute" }
  }
}

module "node_a" {
  source           = "./modules/node"
  providers        = { aws = aws.a }
  name             = "mb-${var.region_a}"
  vpc_cidr         = "10.10.0.0/24"
  instance_type    = var.instance_type
  volume_gb        = var.volume_gb
  instance_profile = var.instance_profile
}

module "node_b" {
  source           = "./modules/node"
  providers        = { aws = aws.b }
  name             = "mb-${var.region_b}"
  vpc_cidr         = "10.20.0.0/24"
  instance_type    = var.instance_type
  volume_gb        = var.volume_gb
  instance_profile = var.instance_profile
}
