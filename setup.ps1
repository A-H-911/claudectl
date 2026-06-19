#!/usr/bin/env pwsh
# setup.ps1 — install claudectl on Windows
$ErrorActionPreference = "Stop"

$BIN = if ($env:CLAUDECTL_BIN) { $env:CLAUDECTL_BIN } else { "$env:USERPROFILE\.local\bin" }
$SRC = Join-Path $PSScriptRoot "scripts"

if (-not (Test-Path "$SRC\claudectl.ps1")) {
    Write-Error "scripts\claudectl.ps1 not found — run from the repo root"
    exit 1
}

# Check for Claude Code
$claudeBin = "$BIN\claude.exe"
if (-not (Test-Path $claudeBin) -and -not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "warning: Claude Code not found at $claudeBin or in PATH"
    Write-Host "  Install Claude Code first: https://claude.ai/download"
    Write-Host "  Then re-run: .\setup.ps1`n"
}

New-Item -ItemType Directory -Path $BIN -Force | Out-Null
Copy-Item "$SRC\claudectl.ps1" "$BIN\claudectl.ps1" -Force
Copy-Item "$SRC\claudectl.cmd" "$BIN\claudectl.cmd" -Force
Write-Host "installed claudectl.ps1 and claudectl.cmd to $BIN"

# Idempotent PATH setup
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$BIN*") {
    [Environment]::SetEnvironmentVariable("PATH", "$BIN;$userPath", "User")
    Write-Host "added $BIN to user PATH — open a new terminal to activate"
} else {
    Write-Host "$BIN is already in PATH"
}

Write-Host ""
Write-Host "claudectl is ready. Run: claudectl help"
Write-Host ""
Write-Host "Note: if execution policy blocks scripts, run:"
Write-Host "  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
