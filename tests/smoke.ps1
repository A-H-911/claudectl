#!/usr/bin/env pwsh
# smoke.ps1 — real-machine end-to-end smoke test for claudectl (Windows).
#
# Mirror of smoke.sh: drives the full lifecycle on a real Windows box, inside a
# temp sandbox (CLAUDECTL_BASE/CLAUDECTL_BIN -> temp dirs) so it never touches the
# real %USERPROFILE%\.claude-instances or \.local\bin. When CLAUDECTL_SMOKE_REAL_CLAUDE=1
# and a real `claude.exe`/`claude` is on PATH, it also exercises the real spawn path.
#
# Usage (works under Windows PowerShell 5.1 AND pwsh 7):
#   powershell -NoProfile -File tests\smoke.ps1
#   $env:CLAUDECTL_SMOKE_REAL_CLAUDE=1; pwsh -NoProfile -File tests\smoke.ps1
#
# Exit 0 iff every assertion passes.

$ErrorActionPreference = "Continue"

$REPO_ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SCRIPT    = "$REPO_ROOT\scripts\claudectl.ps1"
if (-not (Test-Path $SCRIPT)) { Write-Host "smoke: cannot find scripts\claudectl.ps1 at $SCRIPT"; exit 2 }

# ── Sandbox ─────────────────────────────────────────────────────────────────────
$TMPROOT = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TMPROOT -Force | Out-Null
$env:CLAUDECTL_BASE = "$TMPROOT\instances"
$env:CLAUDECTL_BIN  = "$TMPROOT\bin"
New-Item -ItemType Directory -Path $env:CLAUDECTL_BASE -Force | Out-Null
New-Item -ItemType Directory -Path $env:CLAUDECTL_BIN  -Force | Out-Null

$pass = 0; $fail = 0
function ok   { param([string]$m) Write-Host "  PASS $m" -ForegroundColor Green; $script:pass++ }
function err  { param([string]$l,[string]$d) Write-Host "  FAIL ${l}: $d" -ForegroundColor Red; $script:fail++ }
function note { param([string]$m) Write-Host "  NOTE $m" -ForegroundColor Yellow }
function run  { powershell -NoProfile -ExecutionPolicy Bypass -File $SCRIPT @args }

# Provision the sandbox claude the launcher will invoke.
$realClaude = (Get-Command claude -ErrorAction SilentlyContinue)
$REAL_EXEC = $false
if ($env:CLAUDECTL_SMOKE_REAL_CLAUDE -eq "1" -and $realClaude) {
    Copy-Item $realClaude.Source "$env:CLAUDECTL_BIN\claude.exe" -Force
    $REAL_EXEC = $true
    note "real-claude mode: launcher will invoke $($realClaude.Source)"
} else {
    # Stub batch that identifies itself, so we can prove --dry-run did NOT invoke it.
    Set-Content "$env:CLAUDECTL_BIN\claude.exe" "@echo off`r`necho [smoke-stub-claude] %*" -Encoding ascii
}

Write-Host "`n=== claudectl smoke: Windows ($([System.Environment]::OSVersion.Version)) PS$($PSVersionTable.PSVersion) ==="

# ── add ─────────────────────────────────────────────────────────────────────────
run add smoke *> $null
if (Test-Path "$env:CLAUDECTL_BASE\smoke" -PathType Container) { ok "add: config dir created" } else { err "add:dir" "missing" }
if (Test-Path "$env:CLAUDECTL_BIN\claude-smoke.cmd")           { ok "add: launcher created"   } else { err "add:launcher" "missing" }
$lc = Get-Content "$env:CLAUDECTL_BIN\claude-smoke.cmd" -Raw
if ($lc -like "*CLAUDE_CONFIG_DIR*")          { ok "add: launcher sets CLAUDE_CONFIG_DIR" } else { err "add:env" "missing" }
if ($lc -like "*$($env:CLAUDECTL_BIN)*")      { ok "add: launcher points at sandbox bin"  } else { err "add:binpath" "hardcoded path" }

# ── list ────────────────────────────────────────────────────────────────────────
$out = run list
if ($out -like "*smoke*")   { ok "list: shows instance" } else { err "list" "instance missing" }
if ($out -like "*vanilla*") { ok "list: shows vanilla"  } else { err "list:vanilla" "missing" }
try {
    $j = run list --json | ConvertFrom-Json
    if ($j | Where-Object { $_.name -eq "smoke" }) { ok "list --json: valid, contains smoke" } else { err "list --json" "missing smoke" }
} catch { err "list --json" "invalid JSON" }

# ── config round-trip ───────────────────────────────────────────────────────────
run config smoke model "claude-opus-4-8" *> $null
$val = run config smoke model
if ("$val".Trim() -eq "claude-opus-4-8") { ok "config: write/read round-trip" } else { err "config" "got '$val'" }

# ── clone (security) ────────────────────────────────────────────────────────────
run add smoke2 *> $null
Set-Content "$env:CLAUDECTL_BASE\smoke\.credentials.json" '{"oauthToken":"SMOKETOKEN"}' -Encoding utf8
run clone smoke smoke2 *> $null
if (Test-Path "$env:CLAUDECTL_BASE\smoke2\settings.json")              { ok "clone: settings.json copied" } else { err "clone:settings" "not copied" }
if (-not (Test-Path "$env:CLAUDECTL_BASE\smoke2\.credentials.json"))   { ok "clone: credentials NOT copied (security)" } else { err "clone:creds" "SECURITY VIOLATION" }

# ── token (path only, never the value) ──────────────────────────────────────────
$tok = run token smoke 2>&1; $code = $LASTEXITCODE
if ($code -eq 0 -and ($tok -like "*.credentials.json*")) { ok "token: prints credentials path" } else { err "token:path" "exit $code" }
if ($tok -notlike "*SMOKETOKEN*") { ok "token: does NOT leak the token value" } else { err "token:leak" "SECURITY VIOLATION: token value printed" }
Remove-Item "$env:CLAUDECTL_BASE\smoke\.credentials.json" -Force -ErrorAction SilentlyContinue

# ── status ──────────────────────────────────────────────────────────────────────
$null = run status; if ($LASTEXITCODE -eq 0) { ok "status: exits 0" } else { err "status" "non-zero" }
try { $null = run status --json | ConvertFrom-Json; ok "status --json: valid" } catch { err "status --json" "invalid" }

# ── spawn --dry-run must NOT execute ────────────────────────────────────────────
$dry = run spawn smoke --dry-run 2>&1
if ($dry -like "*claude-smoke*")        { ok "spawn --dry-run: prints launcher" } else { err "spawn:dry-path" "launcher missing" }
if ($dry -notlike "*smoke-stub-claude*") { ok "spawn --dry-run: did not execute" } else { err "spawn:dry-exec" "executed!" }

# ── spawn real exec (optional) ──────────────────────────────────────────────────
if ($REAL_EXEC) {
    $null = run spawn smoke -- --version 2>&1; $code = $LASTEXITCODE
    if ($code -eq 0) { ok "spawn -- --version: real exec exits 0" } else { err "spawn:real" "exit $code" }
} else {
    note "real-claude mode off: skipping real spawn exec (set CLAUDECTL_SMOKE_REAL_CLAUDE=1)"
}

# ── remove ──────────────────────────────────────────────────────────────────────
run remove smoke --force *> $null
if (-not (Test-Path "$env:CLAUDECTL_BIN\claude-smoke.cmd")) { ok "remove: launcher removed" } else { err "remove" "still present" }

# ── Cleanup + summary ───────────────────────────────────────────────────────────
Remove-Item -Path $TMPROOT -Recurse -Force -ErrorAction SilentlyContinue
$env:CLAUDECTL_BASE = $null; $env:CLAUDECTL_BIN = $null
Write-Host ""
Write-Host "smoke: $pass passed, $fail failed"
if ($fail -eq 0) { exit 0 } else { exit 1 }
