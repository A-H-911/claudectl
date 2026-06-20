#!/usr/bin/env pwsh
# setup.ps1 — install claudectl on Windows
$ErrorActionPreference = "Stop"

$BIN = if ($env:CLAUDECTL_BIN) { $env:CLAUDECTL_BIN } else { "$env:USERPROFILE\.local\bin" }
$SRC = Join-Path $PSScriptRoot "scripts"

if (-not (Test-Path "$SRC\claudectl.ps1")) {
    Write-Error "scripts\claudectl.ps1 not found — run from the repo root"
    exit 1
}

New-Item -ItemType Directory -Path $BIN -Force | Out-Null
Copy-Item "$SRC\claudectl.ps1" "$BIN\claudectl.ps1" -Force
Copy-Item "$SRC\claudectl.cmd" "$BIN\claudectl.cmd" -Force
Write-Host "installed claudectl.ps1 and claudectl.cmd to $BIN`n"

# Delegate PATH wiring + verification to the installed CLI (single source of truth).
# CLAUDECTL_BIN is set so the child uses the same install dir as $BIN.
$env:CLAUDECTL_BIN = $BIN
& "$BIN\claudectl.ps1" setup
