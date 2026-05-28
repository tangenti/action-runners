# attest

Build provenance attestation demo using GitHub Actions, a self-hosted runner,
and a local Docker registry.

## What this does

```
┌──────────────────────────────────────────────────────────────────┐
│  Your Mac (Docker Desktop)                                       │
│                                                                  │
│  Docker network "attest"                                         │
│  ┌──────────────────┐              ┌───────────────────┐        │
│  │  gh-runner       │──push image─►│  local-registry   │        │
│  │  (Docker ctnr)   │              │  :5000 (internal) │        │
│  └──────────────────┘              │  :5001 (host)     │        │
│         ▲                          └───────────────────┘        │
│         │ job dispatch                                           │
└─────────┼────────────────────────────────────────────────────────┘
          │
    GitHub Actions
    (triggers workflow on push)
          │
          │  actions/attest-build-provenance@v2
          │    ├─ signs with GitHub Sigstore Fulcio CA
          │    ├─ stores bundle → GitHub Attestations API
          │    └─ pushes bundle as OCI referrer → local-registry:5000
          ▼
    GitHub Attestations API
    (keyed by image SHA256 digest)
```

**Attestation storage:**
- The signed bundle lives in **GitHub's Attestations API** (always).
- It is also pushed as an **OCI 1.1 referrer** into the local registry
  (`push-to-registry: true`), so you can verify from the registry copy with
  `gh attestation verify --bundle-from-oci`.

---

## Prerequisites

```sh
brew install gh oras
brew install --cask docker   # Docker Desktop
gh auth login                # authenticate via browser
```

---

## Step 1 — Start Docker Desktop

Open it from Applications and wait for the menu bar whale to stop animating.

---

## Step 2 — Start the local registry

```sh
chmod +x scripts/setup-registry.sh scripts/teardown.sh scripts/setup-runner.sh
./scripts/setup-registry.sh
```

Creates:
- Docker network **`attest`**
- Container **`local-registry`** → `localhost:5001` on your Mac,
  `local-registry:5000` from any container on the `attest` network

Verify:
```sh
curl http://localhost:5001/v2/_catalog
# → {"repositories":[]}
```

---

## Step 3 — Get a runner registration token from GitHub UI

No PAT or stored credential needed. GitHub issues a one-time ephemeral token
(expires in 1 hour) directly from the UI.

1. Go to:
   ```
   https://github.com/<GITHUB_OWNER>/<GITHUB_REPO>/settings/actions/runners/new
   ```
2. Select **Linux** / **x64**
3. In the **Configure** section, find the `--token` line. Copy the token value
   — it starts with `AART...`

---

## Step 4 — Start the self-hosted runner

The runner is a Docker container on the `attest` network. It mounts the host
Docker socket so it can run `docker build` and `docker push`. Because it is on
the same network as `local-registry`, it can push to `local-registry:5000`
directly. It also reaches GitHub's OIDC endpoint for real Sigstore signing.

```sh
export GITHUB_OWNER=<your-github-username-or-org>
export GITHUB_REPO=<your-repo-name>
export REGISTRATION_TOKEN=<token copied from GitHub UI in step 3>

./scripts/setup-runner.sh
```

Verify the runner appears in GitHub as **Idle**:
```
https://github.com/<GITHUB_OWNER>/<GITHUB_REPO>/settings/actions/runners
```

---

## Step 5 — Push to GitHub

The `on: push` trigger fires the workflow on every push. The workflow file must
exist on the default branch first:

```sh
git remote add origin https://github.com/<GITHUB_OWNER>/<GITHUB_REPO>.git
git add .
git commit -m "feat: hello-server with build provenance attestation"
git push -u origin main
```

Watch the run:
```sh
gh run watch --repo <GITHUB_OWNER>/<GITHUB_REPO>
```

Or trigger manually any time after the first push:
```sh
gh workflow run build-attest.yml \
  --repo <GITHUB_OWNER>/<GITHUB_REPO> \
  --ref main
```

---

## Step 6 — Get the image digest

```sh
# From the workflow run logs
gh run view --repo <GITHUB_OWNER>/<GITHUB_REPO> --log | grep "Digest:"

# Or from the registry API
COMMIT=$(git rev-parse HEAD)
curl -s "http://localhost:5001/v2/hello-server/manifests/${COMMIT}" \
  -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  | python3 -c "
import sys, hashlib
body = sys.stdin.buffer.read()
print('sha256:' + hashlib.sha256(body).hexdigest())
"
```

Set it:
```sh
DIGEST=sha256:<hex>
```

---

## Step 7 — Verify the attestation

### A) From GitHub's Attestations API (default)

```sh
gh attestation verify \
  oci://localhost:5001/hello-server@${DIGEST} \
  --repo <GITHUB_OWNER>/<GITHUB_REPO>
```

Expected output:
```
Loaded digest sha256:... for oci://localhost:5001/hello-server@sha256:...
Loaded 1 attestation from GitHub API
✓ Verification succeeded!

The following checks passed:
  - The artifact's signature was issued by GitHub's artifact attestations service
  - The artifact matches the GitHub repo <GITHUB_OWNER>/<GITHUB_REPO>
```

### B) From the OCI referrer in the local registry (no GitHub API)

```sh
gh attestation verify \
  oci://localhost:5001/hello-server@${DIGEST} \
  --repo <GITHUB_OWNER>/<GITHUB_REPO> \
  --bundle-from-oci
```

### C) Inspect the raw SLSA provenance bundle

```sh
gh attestation download \
  oci://localhost:5001/hello-server@${DIGEST} \
  --repo <GITHUB_OWNER>/<GITHUB_REPO>

# Decode the in-toto statement
cat sha256:*.jsonl | python3 -c "
import sys, json, base64
bundle = json.load(sys.stdin)
payload = json.loads(base64.b64decode(bundle['dsseEnvelope']['payload'] + '=='))
print(json.dumps(payload, indent=2))
"
```

### D) List OCI referrers attached to the image

```sh
oras discover localhost:5001/hello-server@${DIGEST} --format tree
```

Expected:
```
localhost:5001/hello-server@sha256:...
└── application/vnd.dev.sigstore.bundle.v0.3+json
    └── sha256:...
```

---

## Teardown

```sh
./scripts/teardown.sh

# Remove the stale runner entry from GitHub
gh api repos/<GITHUB_OWNER>/<GITHUB_REPO>/actions/runners   # find the ID
gh api -X DELETE repos/<GITHUB_OWNER>/<GITHUB_REPO>/actions/runners/<ID>
```

---

## File structure

```
.
├── cmd/server/main.go                  # Go HTTP server → GET / returns "Hello, World!"
├── Dockerfile                          # Multi-stage build → scratch final image
├── go.mod
├── .github/
│   └── workflows/
│       └── build-attest.yml            # Build + push + attest workflow
└── scripts/
    ├── setup-registry.sh               # Create Docker network + local registry
    ├── setup-runner.sh                 # Start self-hosted runner in Docker
    └── teardown.sh                     # Stop runner + registry + remove network
```

---

## How the attestation works

```
actions/attest-build-provenance@v2
│
├─ 1. Mints a GitHub OIDC JWT (token.actions.githubusercontent.com)
│      Claims: repo, workflow, ref, sha, runner_environment, ...
│
├─ 2. Sends JWT to GitHub's private Sigstore Fulcio CA
│      Fulcio validates the JWT → issues short-lived X.509 cert
│      embedding the workflow identity
│
├─ 3. Creates a DSSE envelope wrapping an in-toto Statement:
│      predicateType: https://slsa.dev/provenance/v1
│      subject: [{name: "hello-server", digest: {sha256: "..."}}]
│      predicate: {builder, buildDefinition, runDetails}
│
├─ 4. Signs the envelope with the Fulcio-issued ephemeral key
│
├─ 5. Records a signed timestamp (private repos: no public Rekor log)
│
├─ 6. POSTs the Sigstore bundle to GitHub Attestations API
│      → https://github.com/<owner>/<repo>/attestations
│
└─ 7. (push-to-registry: true) Pushes the bundle as OCI 1.1 referrer
       manifest.subject = {digest: sha256:<image-digest>}
       artifactType = application/vnd.dev.sigstore.bundle.v0.3+json
```

---

## Known constraints

| Constraint | Notes |
|---|---|
| `registry:2` OCI 1.1 support | v2.8.3+ supports the Referrers API. The setup script pulls `registry:2` (latest). If `--bundle-from-oci` returns 404, force-pull a newer image: `docker pull registry:2`. |
| Private repo attestations | Private repos use GitHub's private Sigstore CA with no public Rekor log. `gh attestation verify` handles this automatically. `cosign verify-attestation` additionally needs `gh attestation trusted-root > trusted_root.jsonl` and `--trusted-root trusted_root.jsonl`. |
| Runner OIDC reachability | The runner container needs outbound HTTPS to `token.actions.githubusercontent.com`, `fulcio.githubapp.com`, and `api.github.com`. Docker Desktop on Mac allows this by default. |
| Port 5000 on macOS | macOS Monterey+ reserves port 5000 for AirPlay Receiver. The registry is exposed on **5001** on the host; inside Docker it is still 5000. |
