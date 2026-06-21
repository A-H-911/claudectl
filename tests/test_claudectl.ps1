#!/usr/bin/env pwsh
# Physical integration tests for claudectl (PowerShell / Windows).
# Mirror of test_claudectl.sh — same commands, same assertions, PS-native idioms.

$ErrorActionPreference = "Continue"

$REPO_ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SCRIPT    = "$REPO_ROOT\scripts\claudectl.ps1"

# ── Isolation ─────────────────────────────────────────────────────────────────
$TMPROOT = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TMPROOT -Force | Out-Null
$env:CLAUDECTL_BASE = "$TMPROOT\instances"
$env:CLAUDECTL_BIN  = "$TMPROOT\bin"
New-Item -ItemType Directory -Path $env:CLAUDECTL_BASE -Force | Out-Null
New-Item -ItemType Directory -Path $env:CLAUDECTL_BIN  -Force | Out-Null
Copy-Item "$REPO_ROOT\tests\helpers\fake-claude.cmd" "$env:CLAUDECTL_BIN\claude.exe" -Force

$pass = 0; $fail = 0

function ok  { param([string]$msg)                    Write-Host "  PASS $msg" -ForegroundColor Green; $script:pass++ }
function err { param([string]$label,[string]$detail)  Write-Host "  FAIL ${label}: $detail" -ForegroundColor Red; $script:fail++ }
# Drive claudectl.ps1 under the SAME PowerShell that runs this suite, so it can be
# validated under both Windows PowerShell 5.1 (the production claudectl.cmd path) and
# pwsh 7. -ExecutionPolicy Bypass mirrors claudectl.cmd. Override with $env:CLAUDECTL_PS.
$PSExe = if ($env:CLAUDECTL_PS) { $env:CLAUDECTL_PS } else { try { (Get-Process -Id $PID).Path } catch { $null } }
if (-not $PSExe) { $PSExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' } }
function run { & $PSExe -NoProfile -ExecutionPolicy Bypass -File $SCRIPT @args }

# ── add ───────────────────────────────────────────────────────────────────────
Write-Host "`n=== add ==="
run add myinstance
if (Test-Path "$env:CLAUDECTL_BASE\myinstance" -PathType Container) { ok "add: config dir created" } else { err "add:config dir" "missing" }
if (Test-Path "$env:CLAUDECTL_BIN\claude-myinstance.cmd")           { ok "add: launcher created"   } else { err "add:launcher"   "missing" }
$content = Get-Content "$env:CLAUDECTL_BIN\claude-myinstance.cmd" -Raw
if ($content -like "*CLAUDE_CONFIG_DIR*")         { ok "add: launcher sets CLAUDE_CONFIG_DIR"           } else { err "add:env var"      "missing" }
if ($content -like "*$($env:CLAUDECTL_BIN)*")     { ok "add: launcher uses CLAUDECTL_BIN (not hardcoded)" } else { err "add:launcher path" "hardcoded path detected" }

$null = run add myinstance 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "add: duplicate exits non-zero (no --force)" } else { err "add:duplicate" "got exit $code" }

$null = run add "bad name" 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "add: invalid name exits non-zero" } else { err "add:invalid name" "got exit $code" }

run add forcetest *> $null
$null = run add forcetest --force 2>&1; $code = $LASTEXITCODE
if ($code -eq 0) { ok "add --force: reinitialises existing instance (exit 0)" } else { err "add-force:exit" "got exit $code" }
if (Test-Path "$env:CLAUDECTL_BIN\claude-forcetest.cmd") { ok "add --force: launcher present after reinit" } else { err "add-force:launcher" "missing" }

# ── list ──────────────────────────────────────────────────────────────────────
Write-Host "`n=== list ==="
$out = run list
if ($out -like "*myinstance*") { ok "list: shows new instance"   } else { err "list"        "instance not in output" }
if ($out -like "*vanilla*")    { ok "list: always shows vanilla" } else { err "list:vanilla" "missing" }

$jsonRaw = run list --json
try {
    $json = $jsonRaw | ConvertFrom-Json
    if ($json -is [array])                                   { ok "list --json: returns array" }    else { err "list --json" "not an array" }
    $vanilla = $json | Where-Object { $_.name -eq "vanilla" } | Select-Object -First 1
    if ($vanilla)                                            { ok "list --json: vanilla present" }   else { err "list --json:vanilla" "missing" }
    if ($vanilla -and ($vanilla.logged_in -is [bool]))       { ok "list --json: logged_in is bool" } else { err "list --json:bool" "not bool" }
    $inst = $json | Where-Object { $_.name -eq "myinstance" } | Select-Object -First 1
    if ($inst)                                               { ok "list --json: myinstance present" } else { err "list --json:myinstance" "missing" }
    if ($inst -and $inst.config_dir)                         { ok "list --json: config_dir present" } else { err "list --json:config_dir" "missing" }
} catch { err "list --json" "invalid JSON: $jsonRaw" }

# ── path ──────────────────────────────────────────────────────────────────────
Write-Host "`n=== path ==="
$actual = run path myinstance
if ($actual -eq "$env:CLAUDECTL_BASE\myinstance") { ok "path: returns correct dir" }      else { err "path" "got '$actual'" }
$v = run path vanilla
if ($v -like "*.claude*") { ok "path vanilla: returns .claude dir" }                      else { err "path vanilla" "got '$v'" }
$null = run path nonexistent 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "path: exits non-zero for unknown instance" }                       else { err "path:missing" "got exit $code" }

# ── config ────────────────────────────────────────────────────────────────────
Write-Host "`n=== config ==="
$null = run config myinstance; $code = $LASTEXITCODE
if ($code -eq 0) { ok "config: empty instance exits 0" } else { err "config:empty exit" "got $code" }
$result = run config myinstance
try { $null = $result | ConvertFrom-Json; ok "config: empty instance returns valid JSON" } catch { err "config:empty JSON" "not valid JSON" }

run config myinstance model "claude-opus-4-5"; $code = $LASTEXITCODE
if ($code -eq 0) { ok "config write: exits 0" } else { err "config:write exit" "got $code" }
if (Test-Path "$env:CLAUDECTL_BASE\myinstance\settings.json") { ok "config write: creates settings.json" } else { err "config:write" "file not created" }
$val = run config myinstance model
if ($val -eq "claude-opus-4-5") { ok "config read-back: correct value" } else { err "config:readback" "got '$val'" }

$val = run config myinstance no_such_key; $code = $LASTEXITCODE
if ($code -eq 0 -and [string]::IsNullOrWhiteSpace([string]$val)) { ok "config: absent key returns empty" } else { err "config:absent-key" "exit $code, got '$val'" }

# ── clone ─────────────────────────────────────────────────────────────────────
Write-Host "`n=== clone ==="
$null = run clone myinstance nonexistent 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "clone: exits non-zero if dst doesn't exist" } else { err "clone:missing-dst" "got exit $code" }

run add clonetest
Set-Content "$env:CLAUDECTL_BASE\myinstance\.credentials.json" '{"oauthToken":"SECRET"}' -Encoding utf8
run clone myinstance clonetest
if (Test-Path "$env:CLAUDECTL_BASE\clonetest\settings.json")          { ok "clone: settings.json copied" }              else { err "clone:settings" "not copied" }
if (-not (Test-Path "$env:CLAUDECTL_BASE\clonetest\.credentials.json")) { ok "clone: .credentials.json NOT copied"       } else { err "clone:credentials" "SECURITY VIOLATION: credentials copied!" }

# clone --deep: copies non-denylisted files/dirs, excludes credentials + cache
run add deepsrc; run add deepdst
Set-Content "$env:CLAUDECTL_BASE\deepsrc\settings.json" '{"theme":"dark"}' -Encoding utf8
New-Item -ItemType Directory "$env:CLAUDECTL_BASE\deepsrc\plugins" -Force | Out-Null
Set-Content "$env:CLAUDECTL_BASE\deepsrc\plugins\p.txt" "x" -Encoding utf8
New-Item -ItemType Directory "$env:CLAUDECTL_BASE\deepsrc\cache" -Force | Out-Null
Set-Content "$env:CLAUDECTL_BASE\deepsrc\cache\c.bin" "x" -Encoding utf8
Set-Content "$env:CLAUDECTL_BASE\deepsrc\.credentials.json" '{"oauthToken":"SECRET"}' -Encoding utf8
run clone deepsrc deepdst --deep
if (Test-Path "$env:CLAUDECTL_BASE\deepdst\settings.json")             { ok "clone --deep: settings.json copied" }      else { err "clone-deep:settings" "not copied" }
if (Test-Path "$env:CLAUDECTL_BASE\deepdst\plugins\p.txt")            { ok "clone --deep: non-denylisted dir copied" } else { err "clone-deep:plugins" "not copied" }
if (-not (Test-Path "$env:CLAUDECTL_BASE\deepdst\cache"))             { ok "clone --deep: cache/ excluded (denylist)" } else { err "clone-deep:cache" "cache copied" }
if (-not (Test-Path "$env:CLAUDECTL_BASE\deepdst\.credentials.json")) { ok "clone --deep: .credentials.json excluded (security)" } else { err "clone-deep:credentials" "SECURITY VIOLATION: credentials deep-copied!" }

# clone (shallow) when src has no settings.json: prints a 'nothing to clone' note, exits 0
run add nosettings; run add nosettingsdst
$out = run clone nosettings nosettingsdst 2>&1; $code = $LASTEXITCODE
if ($code -eq 0 -and ($out -like "*nothing to clone*")) { ok "clone: no settings.json -> 'nothing to clone' note (exit 0)" } else { err "clone:no-settings" "exit ${code}: $out" }

# ── spawn ─────────────────────────────────────────────────────────────────────
Write-Host "`n=== spawn ==="
$out = run spawn myinstance --dry-run 2>&1
if ($out -like "*claude-myinstance*") { ok "spawn --dry-run: prints launcher path" } else { err "spawn --dry-run:path" "launcher not in output" }
if ($out -notlike "*fake-claude*")    { ok "spawn --dry-run: did not execute"       } else { err "spawn --dry-run" "actually exec'd!" }

$null = run spawn no-such-instance --dry-run 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "spawn: exits non-zero for missing instance" } else { err "spawn:missing" "got exit $code" }

$null = run spawn myinstance --project "C:\NoSuchDir" --dry-run 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "spawn --project: exits non-zero for missing dir" } else { err "spawn:missing-dir" "got exit $code" }

$out = run spawn myinstance --dry-run -- --bare -p "hello" 2>&1
if ($out -like "*--bare*") { ok "spawn --dry-run: passes through claude args after --" } else { err "spawn:passthrough" "args not in output: $out" }

$null = run spawn myinstance --bogus-flag --dry-run 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "spawn: unknown flag exits non-zero" } else { err "spawn:unknown-flag" "got exit $code" }

# ── status ────────────────────────────────────────────────────────────────────
Write-Host "`n=== status ==="
$null = run status; $code = $LASTEXITCODE
if ($code -eq 0) { ok "status: exits 0" } else { err "status:exit" "got $code" }
try { $null = run status --json | ConvertFrom-Json; ok "status --json: valid JSON" } catch { err "status --json" "invalid JSON" }

# ── token ─────────────────────────────────────────────────────────────────────
Write-Host "`n=== token ==="
Remove-Item "$env:CLAUDECTL_BASE\myinstance\.credentials.json" -Force -ErrorAction SilentlyContinue
$null = run token myinstance 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "token: exits non-zero when not logged in" } else { err "token:loggedout" "got exit $code" }

Set-Content "$env:CLAUDECTL_BASE\myinstance\.credentials.json" '{"oauthToken":"test-token"}' -Encoding utf8
$out = run token myinstance 2>&1; $code = $LASTEXITCODE
if ($code -eq 0)              { ok "token: exits 0 when logged in" }   else { err "token:exit" "got $code" }
if ($out -like "*OAUTH*")     { ok "token: prints CI usage hint"    }   else { err "token:hint" "CI hint missing" }
Remove-Item "$env:CLAUDECTL_BASE\myinstance\.credentials.json" -Force -ErrorAction SilentlyContinue

# ── version ───────────────────────────────────────────────────────────────────
Write-Host "`n=== version ==="
$out = run version; $code = $LASTEXITCODE
if ($code -eq 0)               { ok "version: exits 0" }                     else { err "version:exit" "got $code" }
if ($out -like "*claudectl*")  { ok "version: output contains 'claudectl'" } else { err "version:output" "missing" }

# ── reset ─────────────────────────────────────────────────────────────────────
Write-Host "`n=== reset ==="
Set-Content "$env:CLAUDECTL_BASE\myinstance\settings.json" '{"theme":"dark"}' -Encoding utf8
run reset myinstance --force
if (Test-Path "$env:CLAUDECTL_BASE\myinstance" -PathType Container)    { ok "reset: config dir preserved" } else { err "reset:dir"      "dir gone" }
if (-not (Test-Path "$env:CLAUDECTL_BASE\myinstance\settings.json"))   { ok "reset: settings.json wiped"  } else { err "reset:settings" "still exists" }
if (Test-Path "$env:CLAUDECTL_BIN\claude-myinstance.cmd")              { ok "reset: launcher kept"         } else { err "reset:launcher" "launcher removed" }
$null = run reset vanilla 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "reset vanilla: exits non-zero (blocked)" } else { err "reset:vanilla" "got exit $code" }

# ── remove ────────────────────────────────────────────────────────────────────
Write-Host "`n=== remove ==="
run remove myinstance --force
if (-not (Test-Path "$env:CLAUDECTL_BIN\claude-myinstance.cmd"))           { ok "remove: launcher removed"   } else { err "remove:launcher" "still exists" }
if (Test-Path "$env:CLAUDECTL_BASE\myinstance" -PathType Container)        { ok "remove: config dir kept"    } else { err "remove:config"   "dir removed unexpectedly" }

run add fullremove
run remove fullremove --purge --force
if (-not (Test-Path "$env:CLAUDECTL_BIN\claude-fullremove.cmd")) { ok "remove --purge: launcher removed"   } else { err "remove-purge:launcher" "" }
if (-not (Test-Path "$env:CLAUDECTL_BASE\fullremove"))           { ok "remove --purge: config dir removed" } else { err "remove-purge:config" "still exists" }

$null = run remove vanilla 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "remove vanilla: exits non-zero (blocked)" } else { err "remove:vanilla" "got exit $code" }

# ── error handling ────────────────────────────────────────────────────────────
Write-Host "`n=== error handling ==="
$null = run no-such-command 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "unknown command: exits non-zero" } else { err "unknown command" "got exit 0" }

# ── help ──────────────────────────────────────────────────────────────────────
Write-Host "`n=== help ==="
foreach ($cmd in @("add","list","path","reset","remove","spawn","status","clone","config","token","version","setup")) {
    $null = run help $cmd 2>&1; $code = $LASTEXITCODE
    if ($code -eq 0) { ok "help ${cmd}: exits 0" } else { err "help $cmd" "got exit $code" }
}
$null = run help no-such-subcommand 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "help: unknown subcommand exits non-zero" } else { err "help:unknown" "got exit $code" }

# ── missing-name usage errors ──────────────────────────────────────────────────
# Every name-taking command must exit non-zero when invoked with no name.
Write-Host "`n=== missing-name usage ==="
foreach ($c in @("add","path","reset","remove","spawn","clone","config","token")) {
    $null = run $c 2>&1; $code = $LASTEXITCODE
    if ($code -ne 0) { ok "${c}: missing name exits non-zero" } else { err "$c:missing-name" "got exit $code" }
}

# ── instance-not-found errors ───────────────────────────────────────────────────
# Assert-Instance must reject unknown instances. clone checks <src> before <dst>.
Write-Host "`n=== instance not found ==="
$null = run reset ghost --force 2>&1;  $code = $LASTEXITCODE; if ($code -ne 0) { ok "reset: unknown instance exits non-zero" }  else { err "reset:ghost"  "got exit $code" }
$null = run remove ghost --force 2>&1; $code = $LASTEXITCODE; if ($code -ne 0) { ok "remove: unknown instance exits non-zero" } else { err "remove:ghost" "got exit $code" }
$null = run config ghost 2>&1;         $code = $LASTEXITCODE; if ($code -ne 0) { ok "config: unknown instance exits non-zero" } else { err "config:ghost" "got exit $code" }
$null = run token ghost 2>&1;          $code = $LASTEXITCODE; if ($code -ne 0) { ok "token: unknown instance exits non-zero" }  else { err "token:ghost"  "got exit $code" }
$null = run clone ghost-src ghost-dst 2>&1; $code = $LASTEXITCODE; if ($code -ne 0) { ok "clone: unknown src exits non-zero" } else { err "clone:ghost-src" "got exit $code" }

# ── spawn: launcher-missing branch ──────────────────────────────────────────────
# Instance dir exists but the launcher was deleted -> spawn must refuse.
Write-Host "`n=== spawn launcher-missing ==="
run add launchergone *> $null
Remove-Item "$env:CLAUDECTL_BIN\claude-launchergone.cmd" -Force -ErrorAction SilentlyContinue
$null = run spawn launchergone --dry-run 2>&1; $code = $LASTEXITCODE
if ($code -ne 0) { ok "spawn: missing launcher exits non-zero" } else { err "spawn:launcher-missing" "got exit $code" }

# ── spawn: valid --project + --dry-run ──────────────────────────────────────────
# Exercises the Push-Location branch (only the missing-dir path was tested before).
Write-Host "`n=== spawn --project (valid) ==="
$PROJDIR = Join-Path $TMPROOT "projdir"; New-Item -ItemType Directory -Path $PROJDIR -Force | Out-Null
run add projinst *> $null
$out = run spawn projinst --project "$PROJDIR" --dry-run 2>&1; $code = $LASTEXITCODE
if ($code -eq 0 -and ($out -like "*claude-projinst*")) { ok "spawn --project (valid dir): dry-run prints launcher (exit 0)" } else { err "spawn:project-valid" "exit ${code}: $out" }

# NOTE: the interactive confirm-abort case (reset/remove answering 'n') is bash-only.
# PowerShell's Read-Host does not reliably consume redirected stdin across pwsh
# versions, so asserting it here would be flaky. Invariant #5 covers CLI-command
# parity, not test-for-test parity; the abort behaviour is verified in test_claudectl.sh.

# ── dispatch aliases & no-arg default ───────────────────────────────────────────
# ls->list, rm->remove, --version->version, --help/-h->help, bare invocation->help.
Write-Host "`n=== dispatch aliases ==="
$out = run ls
if ($out -like "*vanilla*") { ok "alias: 'ls' dispatches to list" } else { err "alias:ls" "vanilla not in output" }
run add rmalias *> $null
run rm rmalias --force *> $null
if (-not (Test-Path "$env:CLAUDECTL_BIN\claude-rmalias.cmd")) { ok "alias: 'rm' dispatches to remove" } else { err "alias:rm" "launcher still present" }
$out = run --version
if ($out -like "*claudectl*") { ok "alias: '--version' dispatches to version" } else { err "alias:--version" "missing" }
$out = run --help
if ($out -like "*usage:*") { ok "alias: '--help' dispatches to help" } else { err "alias:--help" "no usage banner" }
$out = run -h
if ($out -like "*usage:*") { ok "alias: '-h' dispatches to help" } else { err "alias:-h" "no usage banner" }
$out = run
if ($out -like "*usage:*") { ok "no-arg invocation defaults to help" } else { err "no-arg" "no usage banner" }

# ── Cleanup ───────────────────────────────────────────────────────────────────
Remove-Item -Path $TMPROOT -Recurse -Force -ErrorAction SilentlyContinue
$env:CLAUDECTL_BASE = $null
$env:CLAUDECTL_BIN  = $null

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Results: $pass passed, $fail failed"
if ($fail -eq 0) { exit 0 } else { exit 1 }
