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

# Why htpasswd auth (even though we don't actually care about security)?
# @sigstore/oci (used by actions/attest-build-provenance with push-to-registry: true)
# crashes with "Invalid challenge: " when the registry doesn't issue a
# WWW-Authenticate header. Plain registry:2 with no auth never issues one.
# htpasswd auth makes the registry return `WWW-Authenticate: Basic realm="..."`
# which @sigstore/oci can parse.
AUTH_DIR="${HOME}/.attest-registry-auth"
REGISTRY_USER="dummy"
REGISTRY_PASS="dummy"

if [ ! -f "${AUTH_DIR}/htpasswd" ]; then
  echo "==> Generating htpasswd file (user: ${REGISTRY_USER})..."
  mkdir -p "${AUTH_DIR}"
  docker run --rm --entrypoint htpasswd httpd:2 \
    -Bbn "${REGISTRY_USER}" "${REGISTRY_PASS}" > "${AUTH_DIR}/htpasswd"
fi

if docker inspect "${REGISTRY_NAME}" &>/dev/null; then
  echo "==> Registry '${REGISTRY_NAME}' already running, skipping."
else
  echo "==> Starting local OCI registry on localhost:${REGISTRY_PORT_HOST}..."
  docker run -d \
    --restart=always \
    --name "${REGISTRY_NAME}" \
    --network "${NETWORK}" \
    -p "127.0.0.1:${REGISTRY_PORT_HOST}:${REGISTRY_PORT_INTERNAL}" \
    -v "${AUTH_DIR}:/auth:ro" \
    -e REGISTRY_AUTH=htpasswd \
    -e REGISTRY_AUTH_HTPASSWD_REALM=Registry \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    registry:2
fi

echo ""
echo "✅ Done!"
echo ""
echo "   Registry endpoint:  localhost:${REGISTRY_PORT_HOST}"
echo "   Credentials:        user=${REGISTRY_USER}  password=${REGISTRY_PASS}"
echo ""
echo "   Log in (writes to ~/.docker/config.json):"
echo "     echo ${REGISTRY_PASS} | docker login localhost:${REGISTRY_PORT_HOST} -u ${REGISTRY_USER} --password-stdin"
echo ""
echo "   Verify:"
echo "     curl -u ${REGISTRY_USER}:${REGISTRY_PASS} http://localhost:${REGISTRY_PORT_HOST}/v2/_catalog"
