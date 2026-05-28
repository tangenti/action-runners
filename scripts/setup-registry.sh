#!/usr/bin/env bash
# setup-registry.sh — Create a shared Docker network + local OCI registry.
#
# After this runs:
#   From your Mac:              localhost:5001
#   From any container on the
#   'attest' Docker network:    local-registry:5000
#
# Why 5001 on the host? Port 5000 is used by AirPlay on macOS Monterey+.
#
# Usage:
#   ./scripts/setup-registry.sh

set -euo pipefail

NETWORK="attest"
REGISTRY_NAME="local-registry"
REGISTRY_PORT_HOST="5001"
REGISTRY_PORT_INTERNAL="5000"

echo "==> Checking prerequisites..."
if ! command -v docker &>/dev/null; then
  echo "ERROR: 'docker' not found. Install Docker Desktop first." >&2
  exit 1
fi

if ! docker info &>/dev/null; then
  echo "ERROR: Docker daemon is not running. Start Docker Desktop first." >&2
  exit 1
fi

# ── 1. Create Docker network ──────────────────────────────────────────────────
if docker network inspect "${NETWORK}" &>/dev/null; then
  echo "==> Network '${NETWORK}' already exists, skipping."
else
  echo "==> Creating Docker network '${NETWORK}'..."
  docker network create "${NETWORK}"
fi

# ── 2. Start the registry container ──────────────────────────────────────────
if docker inspect "${REGISTRY_NAME}" &>/dev/null; then
  echo "==> Registry '${REGISTRY_NAME}' already running, skipping."
else
  echo "==> Starting local OCI registry on localhost:${REGISTRY_PORT_HOST}..."
  docker run -d \
    --restart=always \
    --name "${REGISTRY_NAME}" \
    --network "${NETWORK}" \
    -p "127.0.0.1:${REGISTRY_PORT_HOST}:${REGISTRY_PORT_INTERNAL}" \
    registry:2
fi

echo ""
echo "✅ Done!"
echo ""
echo "   Registry endpoints:"
echo "     From your Mac:             localhost:${REGISTRY_PORT_HOST}"
echo "     From containers on '${NETWORK}' network:  ${REGISTRY_NAME}:${REGISTRY_PORT_INTERNAL}"
echo ""
echo "   Verify:"
echo "     curl http://localhost:${REGISTRY_PORT_HOST}/v2/_catalog"
echo "     # → {\"repositories\":[]}"
