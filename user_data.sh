#!/bin/bash
set -eux

# Install required dependencies
apt update -y
apt install -y curl wget openssl jq

# Generate CSR and key
openssl req -new -newkey rsa:2048 -nodes -keyout /root/worker.key -out /root/worker.csr -subj "/CN=spacelift-worker"

# Upload CSR and retrieve signed certificate
CERT_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer ${SPACELIFT_ACCESS_KEY}" -H "Content-Type: application/json" \
    --data '{"csr": "'$(base64 /root/worker.csr)'", "worker_pool_id": "'"${WORKER_POOL_ID}"'"}' \
    https://api.spacelift.io/v2/worker-pools/"${WORKER_POOL_ID}"/certificate)

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
/usr/local/bin/spacelift-launcher register --worker-pool "${WORKER_POOL_ID}" --cert /root/worker.crt --key /root/worker.key
