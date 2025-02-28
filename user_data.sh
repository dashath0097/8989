#!/bin/bash
set -eux

# Install required dependencies
apt update -y
apt install -y curl wget openssl jq

# Verify required environment variables
SPACELIFT_ACCESS_KEY=${SPACELIFT_ACCESS_KEY:-}
WORKER_POOL_ID=${WORKER_POOL_ID:-}

if [ -z "$SPACELIFT_ACCESS_KEY" ]; then
  echo "Error: SPACELIFT_ACCESS_KEY is not set!"
  exit 1
fi

if [ -z "$WORKER_POOL_ID" ]; then
  echo "Error: WORKER_POOL_ID is not set!"
  exit 1
fi

# Generate CSR and key
openssl req -new -newkey rsa:2048 -nodes -keyout /root/worker.key -out /root/worker.csr -subj "/CN=spacelift-worker"

# Upload CSR and retrieve signed certificate
CERT_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer ${SPACELIFT_ACCESS_KEY}" -H "Content-Type: application/json" \
    --data '{"csr": "'$(base64 /root/worker.csr)'", "worker_pool_id": "'${WORKER_POOL_ID}'"}' \
    https://api.spacelift.io/v2/worker-pools/${WORKER_POOL_ID}/certificate)

# Debug: Print API response
if [ -z "$CERT_RESPONSE" ]; then
  echo "Failed to retrieve certificate. Empty response from API."
  exit 1
fi

echo "Spacelift API Response: $CERT_RESPONSE"

# Validate API response
if ! echo "$CERT_RESPONSE" | jq -e .certificate > /dev/null; then
  echo "Failed to retrieve certificate. Invalid JSON response."
  exit 1
fi

echo "$CERT_RESPONSE" | jq -r .certificate > /root/worker.crt

# Ensure certificate is not empty
if [ ! -s /root/worker.crt ]; then
  echo "Certificate file is empty. Worker registration failed!"
  exit 1
fi

# Download and configure Spacelift Launcher
if ! curl -Lo /usr/local/bin/spacelift-launcher https://downloads.spacelift.io/spacelift-launcher-x86_64; then
  echo "Failed to download Spacelift Launcher!"
  exit 1
fi
chmod +x /usr/local/bin/spacelift-launcher

# Register the worker
if ! /usr/local/bin/spacelift-launcher register --worker-pool "${WORKER_POOL_ID}" --cert /root/worker.crt --key /root/worker.key; then
  echo "Worker registration failed!"
  exit 1
fi
