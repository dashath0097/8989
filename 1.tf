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
  count                  = var.worker_count
  ami                    = var.ami_id
  instance_type          = "t3.medium"
  iam_instance_profile   = data.aws_iam_instance_profile.worker_profile.name

  tags = {
    Name = "Spacelift-Worker-${count.index}"
  }

user_data_replace_on_change = true
user_data = <<-EOF
#!/bin/bash
set -eux

# Inject environment variables
echo "export SPACELIFT_ACCESS_KEY=${var.spacelift_access_key}" >> /etc/profile
echo "export WORKER_POOL_ID=${spacelift_worker_pool.private_workers.id}" >> /etc/profile
source /etc/profile

# Run user_data script
bash /root/user_data.sh
EOF



}

# Fetch existing IAM role if it already exists
data "aws_iam_role" "worker_role" {
  name = "SpaceliftWorkerRole"
}

# Fetch existing IAM instance profile instead of creating a new one
data "aws_iam_instance_profile" "worker_profile" {
  name = "SpaceliftWorkerProfile"
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
