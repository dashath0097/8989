#!/bin/bash
set -euxo pipefail  # Enable strict debugging

# Export variables explicitly to ensure availability
export SPACELIFT_ACCESS_KEY="${SPACELIFT_ACCESS_KEY}"
export WORKER_POOL_ID="${WORKER_POOL_ID}"

# Log the values (useful for debugging, remove if needed)
echo "SPACELIFT_ACCESS_KEY: ${SPACELIFT_ACCESS_KEY}"
echo "WORKER_POOL_ID: ${WORKER_POOL_ID}"

# Install required dependencies
apt update -y
apt install -y curl wget openssl jq

# Check if variables are set
if [[ -z "${SPACELIFT_ACCESS_KEY}" ]]; then
  echo "Error: SPACELIFT_ACCESS_KEY is not set!"
  exit 1
fi

if [[ -z "${WORKER_POOL_ID}" ]]; then
  echo "Error: WORKER_POOL_ID is not set!"
  exit 1
fi

# Generate CSR and key
openssl req -new -newkey rsa:2048 -nodes -keyout /root/worker.key -out /root/worker.csr -subj "/CN=spacelift-worker"

# Verify CSR & Key creation
if [[ ! -f /root/worker.csr || ! -f /root/worker.key ]]; then
  echo "Error: CSR or Key file not created!"
  exit 1
fi

# Upload CSR and retrieve signed certificate
CERT_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${SPACELIFT_ACCESS_KEY}" \
  -H "Content-Type: application/json" \
  --data "{\"csr\": \"$(base64 -w 0 /root/worker.csr)\", \"worker_pool_id\": \"${WORKER_POOL_ID}\"}" \
  https://api.spacelift.io/v2/worker-pools/${WORKER_POOL_ID}/certificate)

# Debug: Print API response
echo "Spacelift API Response: $CERT_RESPONSE"

# Validate API response & extract certificate
if [[ -z "$CERT_RESPONSE" ]] || ! echo "$CERT_RESPONSE" | jq -e .certificate > /dev/null; then
  echo "Failed to retrieve certificate. Invalid response from API."
  exit 1
fi

echo "$CERT_RESPONSE" | jq -r .certificate > /root/worker.crt

# Ensure certificate is not empty
if [[ ! -s /root/worker.crt ]]; then
  echo "Error: Certificate file is empty. Worker registration failed!"
  exit 1
fi

# Download and configure Spacelift Launcher
if ! curl -Lo /usr/local/bin/spacelift-launcher https://downloads.spacelift.io/spacelift-launcher-x86_64; then
  echo "Error: Failed to download Spacelift Launcher!"
  exit 1
fi

chmod +x /usr/local/bin/spacelift-launcher

# Register the worker
if ! /usr/local/bin/spacelift-launcher register --worker-pool "${WORKER_POOL_ID}" --cert /root/worker.crt --key /root/worker.key; then
  echo "Error: Worker registration failed!"
  exit 1
fi

echo "✅ Worker successfully registered!"
