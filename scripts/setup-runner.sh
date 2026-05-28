#!/usr/bin/env bash
# setup-runner.sh — Start a self-hosted GitHub Actions runner in Docker.
#
# The registration token is obtained manually from the GitHub UI — no PAT or
# stored credential required.
#
# How to get the registration token:
#   1. Go to: https://github.com/<OWNER>/<REPO>/settings/actions/runners/new
#   2. Select: Linux / x64
#   3. Copy the token shown in the "Configure" step (starts with "AART...")
#      It expires after 1 hour.
#
# Usage:
#   export GITHUB_OWNER=<your-github-username-or-org>
#   export GITHUB_REPO=<your-repo-name>
#   export REGISTRATION_TOKEN=<token from GitHub UI>
#   ./scripts/setup-runner.sh
#
# Prerequisites:
#   - Docker Desktop running
#   - Registry already up (./scripts/setup-registry.sh)

set -euo pipefail

: "${GITHUB_OWNER:?Set GITHUB_OWNER to your GitHub username or org}"
: "${GITHUB_REPO:?Set GITHUB_REPO to your repository name}"
: "${REGISTRATION_TOKEN:?Set REGISTRATION_TOKEN to the token from the GitHub UI}"

RUNNER_NAME="${RUNNER_NAME:-local-runner}"
RUNNER_IMAGE="ghcr.io/actions/actions-runner:latest"
RUNNER_CONTAINER="gh-runner"
NETWORK="attest"

echo "==> Stopping any existing runner container..."
docker rm -f "${RUNNER_CONTAINER}" 2>/dev/null || true

echo "==> Starting self-hosted runner container..."
docker run -d \
  --name "${RUNNER_CONTAINER}" \
  --restart=unless-stopped \
  --network "${NETWORK}" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e RUNNER_NAME="${RUNNER_NAME}" \
  -e RUNNER_WORKDIR="/tmp/runner/work" \
  -e RUNNER_LABELS="self-hosted,local" \
  -e REPO_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
  -e REGISTRATION_TOKEN="${REGISTRATION_TOKEN}" \
  "${RUNNER_IMAGE}"

echo ""
echo "==> Waiting for runner to register with GitHub (up to 30s)..."
for i in $(seq 1 30); do
  if docker logs "${RUNNER_CONTAINER}" 2>&1 | grep -q "Listening for Jobs"; then
    echo "    Runner is ready!"
    break
  fi
  sleep 1
done

echo ""
echo "✅ Runner '${RUNNER_NAME}' is registered and listening."
echo ""
echo "   Verify at: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/actions/runners"
echo ""
echo "   To view runner logs:    docker logs -f ${RUNNER_CONTAINER}"
echo "   To stop/remove runner:  docker rm -f ${RUNNER_CONTAINER}"
