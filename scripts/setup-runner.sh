#!/usr/bin/env bash
# setup-runner.sh — Download, register, and start the official GitHub Actions
# runner binary natively on your Mac. No Docker, no third-party images.
#
# How to get the registration token:
#   1. Go to: https://github.com/<OWNER>/<REPO>/settings/actions/runners/new
#   2. Select: macOS / ARM64 (or x64 on Intel)
#   3. Copy the token shown in the "Configure" step (starts with "AART...").
#      It expires after 1 hour.
#
# Usage:
#   export GITHUB_OWNER=<your-github-username-or-org>
#   export GITHUB_REPO=<your-repo-name>
#   export RUNNER_TOKEN=<token from GitHub UI>
#   ./scripts/setup-runner.sh
#
# The runner runs in the foreground. Ctrl-C to stop.
# To run as a launchd service instead, see the comment at the bottom.

set -euo pipefail

: "${GITHUB_OWNER:?Set GITHUB_OWNER to your GitHub username or org}"
: "${GITHUB_REPO:?Set GITHUB_REPO to your repository name}"
: "${RUNNER_TOKEN:?Set RUNNER_TOKEN to the token from the GitHub UI}"

RUNNER_NAME="${RUNNER_NAME:-local-runner}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,local}"
RUNNER_VERSION="${RUNNER_VERSION:-2.334.0}"
RUNNER_DIR="${RUNNER_DIR:-${HOME}/actions-runner}"

ARCH_RAW=$(uname -m)
case "${ARCH_RAW}" in
  arm64) RUNNER_ARCH="arm64" ;;
  x86_64) RUNNER_ARCH="x64" ;;
  *) echo "ERROR: unsupported arch ${ARCH_RAW}" >&2; exit 1 ;;
esac

TARBALL="actions-runner-osx-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"

REPO_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"

# ── 1. Download + extract runner binary ──────────────────────────────────────
if [ ! -x "${RUNNER_DIR}/run.sh" ]; then
  echo "==> Downloading runner v${RUNNER_VERSION} for osx-${RUNNER_ARCH}..."
  mkdir -p "${RUNNER_DIR}"
  curl -fsSL "${URL}" -o "/tmp/${TARBALL}"
  tar xzf "/tmp/${TARBALL}" -C "${RUNNER_DIR}"
  rm "/tmp/${TARBALL}"
  echo "    Extracted to ${RUNNER_DIR}"
else
  echo "==> Runner binary already present at ${RUNNER_DIR}, skipping download."
fi

cd "${RUNNER_DIR}"

# ── 2. Unconfigure any existing registration ──────────────────────────────────
if [ -f ".runner" ]; then
  echo "==> Found previous registration, removing..."
  ./config.sh remove --token "${RUNNER_TOKEN}" 2>/dev/null \
    || echo "    (remove failed — likely token already used; cleaning files manually)"
  rm -f .runner .credentials .credentials_rsaparams
fi

# ── 3. Register with GitHub ──────────────────────────────────────────────────
echo "==> Registering runner '${RUNNER_NAME}' with ${REPO_URL}..."
./config.sh \
  --url "${REPO_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --work "_work" \
  --unattended \
  --replace

# ── 4. Start the runner (foreground) ─────────────────────────────────────────
echo ""
echo "✅ Registered. Starting runner in foreground (Ctrl-C to stop)..."
echo "   Verify at: ${REPO_URL}/settings/actions/runners"
echo ""
./run.sh

# To run as a launchd service instead of foreground:
#   cd ${RUNNER_DIR}
#   ./svc.sh install
#   ./svc.sh start
#   ./svc.sh status
# To uninstall the service:
#   ./svc.sh stop
#   ./svc.sh uninstall
