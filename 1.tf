terraform {
  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.20.0"
    }
  }
}

provider "spacelift" {}

resource "spacelift_worker_pool" "private_workers" {
  name        = "private-worker-pool"
  description = "Private worker pool for handling secure workloads."
}

provider "aws" {
  region = var.aws_region
}

resource "aws_instance" "spacelift_worker" {
  count         = var.worker_count
  ami           = var.ami_id
  instance_type = "t3.medium"
  iam_instance_profile = aws_iam_instance_profile.worker_profile.name

  tags = {
    Name = "Spacelift-Worker-${count.index}"
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    WORKER_POOL_ID       = spacelift_worker_pool.private_workers.id
    SPACELIFT_ACCESS_KEY = var.spacelift_access_key
  })
}

resource "aws_iam_role" "worker_role" {
  name = "SpaceliftWorkerRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "SpaceliftWorkerProfile"
  role = aws_iam_role.worker_role.name
}

variable "spacelift_access_key" {}
variable "spacelift_secret_key" {}
variable "aws_region" { default = "us-east-1" }
variable "ami_id" {}
variable "worker_count" { default = 2 }

# Ensure user_data.sh is referenced correctly
resource "null_resource" "ensure_user_data_exists" {
  provisioner "local-exec" {
    command = "test -f ${path.module}/user_data.sh || (echo 'user_data.sh not found' && exit 1)"
  }
}
