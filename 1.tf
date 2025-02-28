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
    WORKER_POOL_ID        = spacelift_worker_pool.private_workers.id
    SPACELIFT_ACCESS_KEY  = var.spacelift_access_key
    SPACELIFT_SECRET_KEY  = var.spacelift_secret_key
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

# User Data Script for Worker Registration
data "template_file" "user_data" {
  template = <<EOT
#!/bin/bash
set -eux

# Install required dependencies
apt update -y
apt install -y curl wget openssl jq

# Generate CSR and key
openssl req -new -newkey rsa:2048 -nodes -keyout /root/worker.key -out /root/worker.csr -subj "/CN=spacelift-worker"

# Upload CSR and retrieve signed certificate
CERT_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer ${SPACELIFT_ACCESS_KEY}" -H "Content-Type: application/json" \
    --data '{"csr": "'$(base64 /root/worker.csr)'", "worker_pool_id": "'${WORKER_POOL_ID}'"}' \
    https://api.spacelift.io/v2/worker-pools/${WORKER_POOL_ID}/certificate)

if echo "$CERT_RESPONSE" | jq -e .certificate > /dev/null; then
  echo "$CERT_RESPONSE" | jq -r .certificate > /root/worker.crt
else
  echo "Failed to retrieve certificate: $CERT_RESPONSE"
  exit 1
fi

# Download and configure Spacelift Launcher
curl -Lo /usr/local/bin/spacelift-launcher https://downloads.spacelift.io/spacelift-launcher-x86_64
chmod +x /usr/local/bin/spacelift-launcher

# Register the worker
/usr/local/bin/spacelift-launcher register --worker-pool ${WORKER_POOL_ID} --cert /root/worker.crt --key /root/worker.key
EOT
}
