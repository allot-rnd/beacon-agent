# beacon-agent

**Public install entry point for the Beacon agent.** This repo only hosts the
installer scripts so they can be fetched anonymously — nothing sensitive lives here.
The agent itself is built and published from the private monorepo
[`allot-rnd/beacon`](https://github.com/allot-rnd/beacon) as the **public** GHCR
artifact `ghcr.io/allot-rnd/beacon-agent`.

## Install

**macOS / Linux** (needs `curl`):
```bash
curl -fsSL https://raw.githubusercontent.com/allot-rnd/beacon-agent/main/install.sh | bash
```

**Windows** (PowerShell 7+):
```powershell
irm https://raw.githubusercontent.com/allot-rnd/beacon-agent/main/install.ps1 | iex
```

The installer detects your OS/CPU, pulls the matching agent binary from the public
GHCR artifact (anonymously, digest-verified — **no credential to download**), and
registers it as a background service that turns on Claude Code telemetry and serves
your own dashboard at http://localhost:4318/. It then opens a one-tap **Microsoft
sign-in** so your usage is attributed to you on the board, and auto-updates itself
from the same public artifact from then on.

### ⚠️ After installing, restart Claude Code

The installer enables telemetry for **new** Claude Code sessions. Any Claude Code
that was already running won't send anything until you restart it:

- **Quit and reopen Claude Code** (fully — not just a new conversation).
- If you use the terminal CLI, open a **new** terminal window too.

You should appear on the board within a minute of the next session. If you signed
in but don't show up, this restart is almost always why — the sign-in succeeds
immediately, but telemetry only starts on a fresh session.

## Onboarding & the board

On the corporate network, the gamified onboarding page walks you through the same
steps and drops you onto the leaderboard:

**<https://beacon.allot.local/start>** _(Allot VPN required)_

The command above is all you need — the page is just a friendlier front door and a
link to share with teammates.

## What's private vs public

| | |
|---|---|
| Source code, board image | 🔒 private — `allot-rnd/beacon` |
| Agent binary (`ghcr.io/allot-rnd/beacon-agent`) + these installers | 🌐 public |

The agent binary carries no secrets (the ingest endpoint is internal/VPN-only; the
per-install token is set at install time, not baked into the binary).
