#!/usr/bin/env bash
# teardown.sh — Stop and remove the runner, registry, and Docker network.
#
# Usage:
#   ./scripts/teardown.sh

set -euo pipefail

NETWORK="attest"
REGISTRY_NAME="local-registry"
RUNNER_NAME="gh-runner"

echo "==> Stopping runner container '${RUNNER_NAME}'..."
if docker inspect "${RUNNER_NAME}" &>/dev/null; then
  docker rm -f "${RUNNER_NAME}"
  echo "    Removed."
else
  echo "    Not found, skipping."
fi

echo "==> Stopping registry container '${REGISTRY_NAME}'..."
if docker inspect "${REGISTRY_NAME}" &>/dev/null; then
  docker rm -f "${REGISTRY_NAME}"
  echo "    Removed."
else
  echo "    Not found, skipping."
fi

echo "==> Removing Docker network '${NETWORK}'..."
if docker network inspect "${NETWORK}" &>/dev/null; then
  docker network rm "${NETWORK}"
  echo "    Removed."
else
  echo "    Not found, skipping."
fi

echo ""
echo "✅ Teardown complete."
