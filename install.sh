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

# Tiny JSON helpers so we don't depend on jq — keeps the macOS install brew-free
# (only curl + awk/sed, present by default). json_token pulls .token/.access_token;
# layer_digest finds the digest of the layer titled $1 — the digest precedes the
# title within each layer object, so we take the last digest before the title match.
json_token()   { tr ',' '\n' | sed -nE 's/.*"(access_)?token":"([^"]+)".*/\2/p' | head -1; }
layer_digest() { awk -v a="$1" '{m=m $0} END{n=index(m,"\"org.opencontainers.image.title\":\""a"\""); if(n>0){pre=substr(m,1,n); while(match(pre,/"digest":"sha256:[0-9a-f]+"/)){d=substr(pre,RSTART,RLENGTH); pre=substr(pre,RSTART+RLENGTH)} gsub(/"digest":"|"/,"",d); print d}}'; }

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
  tok="$(curl -fsSL -u "beacon-agent:${BEACON_GH_TOKEN}" "$tokurl" | json_token)" \
    || err "token exchange failed for ${PKG} — check that BEACON_GH_TOKEN has read:packages and isn't expired"
else
  tok="$(curl -fsSL "$tokurl" | json_token)" \
    || err "token exchange failed for ${PKG} — it should be PUBLIC; if it was made private, set BEACON_GH_TOKEN"
fi
[ -n "$tok" ] || err "token endpoint returned no pull token for ${PKG}"
auth=(-H "Authorization: Bearer ${tok}")

# Resolve our platform layer's digest (= sha256 of the binary, also the integrity check).
echo "==> resolving ${PKG}:${TAG}"
digest="$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "https://${registry}/v2/${repo}/manifests/${TAG}" \
  | layer_digest "$asset")" \
  || err "could not read the manifest for ${PKG}:${TAG}"
[ -n "$digest" ] || err "${PKG}:${TAG} has no ${asset} layer"

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

# Sign in with Microsoft SSO to attribute your usage on the board — opens a browser,
# mints BEACON_TOKEN, and bakes it into the agent. Skip with BEACON_NO_LOGIN=1 (e.g.
# headless/CI); non-fatal — the agent still reports without it unless the board
# requires a token, and you can run `beacon-agent login` anytime later.
if [ -n "${BEACON_NO_LOGIN:-}" ]; then
  echo "==> skipping sign-in (BEACON_NO_LOGIN set) — run 'beacon-agent login' later"
else
  echo "==> sign in (Microsoft SSO) to claim your spot on the board"
  "$bin" login || echo "==> sign-in skipped — run 'beacon-agent login' anytime to attribute your usage"
fi

echo "==> optional: install the Beacon tray app from the GitHub Release for at-a-glance level + popover"
