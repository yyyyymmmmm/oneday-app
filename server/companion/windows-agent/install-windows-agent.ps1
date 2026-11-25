# OneDay Windows Agent installer (cloudpc closeout, spec section 5)
# Run ONCE on the target Windows machine, in an ELEVATED PowerShell,
# while logged in interactively (the agent drives the logged-in desktop).
# Engine: CursorTouch/Windows-MCP (MIT), pinned below. This script never
# sends anything anywhere; it installs locally and prints the internal
# auth key ONCE for the operator to file into the companion record
# through the internal path (never through the app, never through chat).
$ErrorActionPreference = 'Stop'

$PIN_VERSION = '0.8.8'   # windows-mcp pinned version (bump deliberately)
$PORT = 8000

# --- 0. preflight -------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Please run this in an elevated (Administrator) PowerShell.' }
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "OS: $($os.Caption) $($os.Version)"
if ([int]$os.BuildNumber -lt 19041) { throw 'Windows 10 2004+ / Windows 11 required.' }
$session = (Get-Process explorer -ErrorAction SilentlyContinue)
if (-not $session) {
  Write-Warning 'No interactive desktop session detected. Desktop tools need a logged-in session: sign in (RDP is fine, disconnect WITHOUT signing out) and re-run.'
}

# --- 1. uv ---------------------------------------------------------------
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-Host 'Installing uv...'
  powershell -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
  $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
}

# --- 2. pinned engine ----------------------------------------------------
Write-Host "Installing windows-mcp==$PIN_VERSION ..."
uv tool install "windows-mcp==$PIN_VERSION" --force

# --- 3. internal auth key + TLS config -----------------------------------
# `windows-mcp auth` generates the internal key, writes
# ~/.windows-mcp/config.toml and (with --with-tls) a self-signed cert.
# The key is INTERNAL: it belongs in the companion record only.
Write-Host 'Generating internal auth key + config...'
windows-mcp auth --transport streamable-http --host 0.0.0.0 --port $PORT --with-tls

# telemetry off (engine reads config.toml; keep data on this machine)
$cfgDir = Join-Path $env:USERPROFILE '.windows-mcp'
Write-Host "Config dir: $cfgDir (server.log / server.error.log live there)"

# --- 4. autostart at login ----------------------------------------------
Write-Host 'Registering login autostart task...'
windows-mcp install --transport streamable-http --host 0.0.0.0 --port $PORT

# --- 5. firewall: port in, operator narrows the source -------------------
$rule = 'OneDay-Windows-Agent'
if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName $rule -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort $PORT | Out-Null
}
Write-Warning "Firewall port $PORT is open to ALL sources right now. Narrow it to the Hermes server IP as soon as you know it:"
Write-Host  "  Set-NetFirewallRule -DisplayName '$rule' -RemoteAddress <HERMES_SERVER_IP>"

# --- 6. local self-check --------------------------------------------------
Write-Host 'Starting the agent now for a local self-check...'
Start-ScheduledTask -TaskName 'windows-mcp-server' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 6
$listening = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue
if ($listening) { Write-Host "OK: port $PORT is listening." }
else { Write-Warning "Port $PORT not listening yet - check $cfgDir\server.error.log" }

Write-Host ''
Write-Host 'DONE. File the endpoint + internal auth key into the companion'
Write-Host 'connection record through the INTERNAL path (companion state),'
Write-Host 'then run the L1-L4 checks in verify-checklist.md.'
Write-Host "Endpoint: https://<this-machine-ip>:$PORT/mcp"
