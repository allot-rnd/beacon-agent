<#
.SYNOPSIS
Beacon agent — installer for Windows (PowerShell 7+).

The agent ships as a PUBLIC GHCR OCI artifact (ghcr.io/allot-rnd/beacon-agent) — no
credential needed. The repo + board image stay private; only the agent binary is
public (it carries no secrets). Run:

  irm https://raw.githubusercontent.com/allot-rnd/beacon-agent/main/install.ps1 | iex

Detects your CPU, pulls the matching beacon-agent layer, and runs
`beacon-agent install` — per-user autostart (onlogon Scheduled Task, or HKCU\Run
where Group Policy blocks it; no admin), telemetry env, dashboard at
http://localhost:4318/. No login, no token.

Requires PowerShell 7+ (its HTTP client drops the auth header on GHCR's cross-host
blob redirect; Windows PowerShell 5.1 may not).
#>
$ErrorActionPreference = 'Stop'

$pkg = if ($env:BEACON_AGENT_PKG) { $env:BEACON_AGENT_PKG } else { 'ghcr.io/allot-rnd/beacon-agent' }
$tag = if ($env:BEACON_AGENT_TAG) { $env:BEACON_AGENT_TAG } else { 'latest' }
$registry = $pkg.Split('/')[0]
$repo = $pkg.Substring($pkg.IndexOf('/') + 1)

$arch = switch -Regex ($env:PROCESSOR_ARCHITECTURE) {
  'ARM64'        { 'arm64'; break }
  'AMD64|x86_64' { 'amd64'; break }
  default        { throw "unsupported CPU '$($env:PROCESSOR_ARCHITECTURE)'" }
}
$asset = "beacon-agent-windows-$arch.exe"

# Pull token: anonymous for the public package; Basic-auth only if BEACON_GH_TOKEN
# is set (private package). GHCR requires this exchange even when anonymous.
# try/catch because $ErrorActionPreference='Stop' makes Invoke-RestMethod throw a
# raw '...status code does not indicate success' on any non-2xx — catch it and emit
# a branch-appropriate hint instead.
$tokUrl = "https://$registry/token?service=$registry&scope=repository:${repo}:pull"
try {
  if ($env:BEACON_GH_TOKEN) {
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("beacon-agent:$($env:BEACON_GH_TOKEN)"))
    $tr = Invoke-RestMethod -Headers @{ Authorization = "Basic $basic" } -Uri $tokUrl -UseBasicParsing
  } else {
    $tr = Invoke-RestMethod -Uri $tokUrl -UseBasicParsing
  }
} catch {
  if ($env:BEACON_GH_TOKEN) {
    throw "token exchange failed for $pkg — check that `$env:BEACON_GH_TOKEN has read:packages and isn't expired ($_)"
  } else {
    throw "token exchange failed for $pkg — it should be PUBLIC; if it was made private, set `$env:BEACON_GH_TOKEN ($_)"
  }
}
$tok = if ($tr.token) { $tr.token } else { $tr.access_token }
if (-not $tok) { throw "token endpoint returned no pull token for $pkg" }

Write-Host "==> resolving $pkg`:$tag"
$mh = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.oci.image.manifest.v1+json' }
$manifest = Invoke-RestMethod -Headers $mh -Uri "https://$registry/v2/$repo/manifests/$tag" -UseBasicParsing
$layer = $manifest.layers | Where-Object { $_.annotations.'org.opencontainers.image.title' -eq $asset } | Select-Object -First 1
if (-not $layer) { throw "$pkg`:$tag has no $asset layer" }
$digest = $layer.digest

# Upgrade-safe: stop any running agent so the locked .exe can be replaced.
try { schtasks /end /tn BeaconAgent   2>$null | Out-Null } catch {}
try { taskkill /im beacon-agent.exe /f 2>$null | Out-Null } catch {}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) 'beacon-agent.exe'
Write-Host "==> downloading $asset ($digest)"
$dh = @{ Authorization = "Bearer $tok"; Accept = 'application/octet-stream' }
Invoke-WebRequest -Headers $dh -Uri "https://$registry/v2/$repo/blobs/$digest" -OutFile $staging -UseBasicParsing

$want = ($digest -replace '^sha256:', '')
$got = (Get-FileHash -Algorithm SHA256 $staging).Hash.ToLower()
if ($got -ne $want) { Remove-Item $staging -Force -ErrorAction SilentlyContinue; throw "checksum mismatch (got $got, want $want)" }

Write-Host '==> installing'
try {
  & $staging install
  # Sign in with Microsoft SSO (opens a browser, mints BEACON_TOKEN, bakes it in).
  # Skip with $env:BEACON_NO_LOGIN; non-fatal — the agent still reports without it
  # unless the board requires a token, and `beacon-agent login` can be run later.
  if ($env:BEACON_NO_LOGIN) {
    Write-Host '==> skipping sign-in (BEACON_NO_LOGIN set) — run "beacon-agent login" later'
  } else {
    Write-Host '==> sign in (Microsoft SSO) to claim your spot on the board'
    try { & $staging login } catch { Write-Host '==> sign-in skipped — run "beacon-agent login" anytime to attribute your usage' }
  }
}
finally { Remove-Item $staging -Force -ErrorAction SilentlyContinue }
