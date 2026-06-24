#!/usr/bin/env bash
# Beacon agent — installer for macOS & Linux.
#
# The agent ships as a PUBLIC GHCR OCI artifact (ghcr.io/allot-rnd/beacon-agent) —
# no credential needed. The repo + the board image stay private; only the agent
# binary is public (it carries no secrets). Bootstrap + run:
#
#   curl -fsSL https://raw.githubusercontent.com/allot-rnd/beacon-agent/main/install.sh | bash
#   # (or: oras pull ghcr.io/allot-rnd/beacon-agent:latest -o b && bash b/install.sh)
#
# Detects your OS/CPU, pulls the matching beacon-agent layer from the artifact, and
# runs `beacon-agent install` — registering a background service (launchd /
# systemd --user), pointing Claude Code's telemetry at it, and serving your own
# dashboard at http://localhost:4318/. No login, no token.
set -euo pipefail

PKG="${BEACON_AGENT_PKG:-ghcr.io/allot-rnd/beacon-agent}"
TAG="${BEACON_AGENT_TAG:-latest}"
registry="${PKG%%/*}"; repo="${PKG#*/}"

err() { printf 'beacon install: %s\n' "$*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || err "curl is required"
command -v jq   >/dev/null 2>&1 || err "jq is required (parses the OCI manifest)"

# --- detect platform -> layer title (matches the release build matrix) ---
os="$(uname -s)"; arch="$(uname -m)"
case "$os" in Darwin) os=darwin ;; Linux) os=linux ;; *) err "unsupported OS '$os' — Windows: use install.ps1" ;; esac
case "$arch" in arm64|aarch64) arch=arm64 ;; x86_64|amd64) arch=amd64 ;; *) err "unsupported CPU '$arch'" ;; esac
asset="beacon-agent-${os}-${arch}"

# Pull token: anonymous for the public package; Basic-auth only if BEACON_GH_TOKEN
# is set (i.e. the package was made private). GHCR requires this exchange even when
# anonymous.
tokurl="https://${registry}/token?service=${registry}&scope=repository:${repo}:pull"
# The `|| err` is load-bearing under `set -euo pipefail`: a curl HTTP failure makes
# the pipeline (and the assignment) non-zero, which would otherwise abort the script
# silently before the empty-check below ever runs.
if [ -n "${BEACON_GH_TOKEN:-}" ]; then
  tok="$(curl -fsSL -u "beacon-agent:${BEACON_GH_TOKEN}" "$tokurl" | jq -r '.token // .access_token // empty')" \
    || err "token exchange failed for ${PKG} — check that BEACON_GH_TOKEN has read:packages and isn't expired"
else
  tok="$(curl -fsSL "$tokurl" | jq -r '.token // .access_token // empty')" \
    || err "token exchange failed for ${PKG} — it should be PUBLIC; if it was made private, set BEACON_GH_TOKEN"
fi
[ -n "$tok" ] || err "token endpoint returned no pull token for ${PKG}"
auth=(-H "Authorization: Bearer ${tok}")

# Resolve our platform layer's digest (= sha256 of the binary, also the integrity check).
echo "==> resolving ${PKG}:${TAG}"
digest="$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "https://${registry}/v2/${repo}/manifests/${TAG}" \
  | jq -r --arg n "$asset" '.layers[] | select(.annotations["org.opencontainers.image.title"]==$n) | .digest')" \
  || err "could not read the manifest for ${PKG}:${TAG}"
[ -n "$digest" ] && [ "$digest" != "null" ] || err "${PKG}:${TAG} has no ${asset} layer"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bin="$tmp/beacon-agent"
echo "==> downloading ${asset} (${digest})"
# The blob 302s to a signed CDN URL on another host; curl drops the auth header on
# that cross-host redirect, so the signed URL downloads cleanly. Do NOT add
# --location-trusted — it would forward the bearer to GHCR's CDN.
curl -fsSL "${auth[@]}" -H "Accept: application/octet-stream" \
  "https://${registry}/v2/${repo}/blobs/${digest}" -o "$bin" || err "download failed"
want="${digest#sha256:}"
got="$( { shasum -a 256 "$bin" 2>/dev/null || sha256sum "$bin"; } | awk '{print $1}')"
[ "$got" = "$want" ] || err "checksum mismatch (got ${got}, want ${want})"
chmod +x "$bin"

# The binary owns the rest: copy into ~/.local/bin, register the service, wire
# telemetry. BEACON_INGEST_URL (if exported) overrides the baked-in org default.
echo "==> installing agent"
"$bin" install

echo "==> optional: install the Beacon tray app from the GitHub Release for at-a-glance level + popover"
