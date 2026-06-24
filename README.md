# beacon-agent

**Public install entry point for the Beacon agent.** This repo only hosts the
installer scripts so they can be fetched anonymously — nothing sensitive lives here.
The agent itself is built and published from the private monorepo
[`allot-rnd/beacon`](https://github.com/allot-rnd/beacon) as the **public** GHCR
artifact `ghcr.io/allot-rnd/beacon-agent`.

## Install — no token, no login

**macOS / Linux** (needs `curl`):
```bash
curl -fsSL https://raw.githubusercontent.com/allot-rnd/beacon-agent/main/install.sh | bash
```

**Windows** (PowerShell 7+):
```powershell
irm https://raw.githubusercontent.com/allot-rnd/beacon-agent/main/install.ps1 | iex
```

The installer detects your OS/CPU, pulls the matching agent binary from the public
GHCR artifact (anonymously, digest-verified), and registers it as a background
service that turns on Claude Code telemetry and serves your own dashboard at
http://localhost:4318/. The agent then auto-updates from the same public artifact —
**no credential ever**.

## What's private vs public

| | |
|---|---|
| Source code, board image | 🔒 private — `allot-rnd/beacon` |
| Agent binary (`ghcr.io/allot-rnd/beacon-agent`) + these installers | 🌐 public |

The agent binary carries no secrets (the ingest endpoint is internal/VPN-only; the
per-install token is set at install time, not baked into the binary).
