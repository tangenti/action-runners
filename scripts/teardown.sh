#!/usr/bin/env bash
# teardown.sh — Stop the registry container and optionally deregister the
# native runner from GitHub.
#
# The runner runs natively on your Mac (not in Docker). If it's running in
# the foreground in another terminal, Ctrl-C it first. If it's installed as a
# launchd service, this script will uninstall it.
#
# Usage:
#   ./scripts/teardown.sh                          # stop registry only
#   RUNNER_TOKEN=AART... ./scripts/teardown.sh    # also deregister from GitHub

set -euo pipefail

REGISTRY_NAME="local-registry"
RUNNER_DIR="${RUNNER_DIR:-${HOME}/actions-runner}"

if [ -d "${RUNNER_DIR}" ] && [ -x "${RUNNER_DIR}/svc.sh" ]; then
  if (cd "${RUNNER_DIR}" && sudo ./svc.sh status 2>&1 | grep -q "started"); then
    echo "==> Stopping launchd runner service..."
    (cd "${RUNNER_DIR}" && sudo ./svc.sh stop && sudo ./svc.sh uninstall) || true
  fi
fi

if [ -n "${RUNNER_TOKEN:-}" ] && [ -f "${RUNNER_DIR}/.runner" ]; then
  echo "==> Deregistering runner from GitHub..."
  (cd "${RUNNER_DIR}" && ./config.sh remove --token "${RUNNER_TOKEN}") \
    || echo "    (deregister failed — remove the runner manually in GitHub UI)"
fi

echo "==> Stopping registry container '${REGISTRY_NAME}'..."
if docker inspect "${REGISTRY_NAME}" &>/dev/null; then
  docker rm -f "${REGISTRY_NAME}"
  echo "    Removed."
else
  echo "    Not found, skipping."
fi

echo ""
echo "✅ Teardown complete."
echo ""
echo "   Runner files are still at: ${RUNNER_DIR}"
echo "   To remove them entirely:   rm -rf ${RUNNER_DIR}"
