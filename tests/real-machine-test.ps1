#!/usr/bin/env pwsh
# real-machine-test.ps1 - run the full claudectl test matrix on real machines over SSH.
#
# WHY: GitHub CI runs on pristine hosts and structurally cannot exercise real-OS
# behavior - Linux /proc per-instance PID attribution, real `exec` spawn, macOS
# bash 3.2 / BSD utilities, and (critically) Windows PowerShell 5.1, which is the
# version the production claudectl.cmd shim actually runs. This orchestrator runs the
# FULL unit suite + the smoke harness on real Linux, macOS, and Windows hosts and
# reports a pass/fail matrix. On Windows it runs the unit suite under BOTH PowerShell
# 5.1 and pwsh 7. Run it on every change (see docs/real-machine-testing.md).
#
# Generic + config-driven: all host specifics live in tests/real-machine-hosts.json
# (gitignored; copy tests/real-machine-hosts.example.json). Credentials are read from
# 1Password (read-only) into in-memory SecureStrings - never printed, never stored.
#
# Run FROM a machine with: PowerShell + the Posh-SSH module + the 1Password CLI (`op`)
# with desktop-app integration unlocked. Each target needs git + SSH. A Windows target
# needs both `powershell` (5.1) and `pwsh` (7) installed to exercise both versions.
#
#   pwsh -File tests/real-machine-test.ps1                 # all hosts, ref from config
#   pwsh -File tests/real-machine-test.ps1 -Ref my-branch  # test a pushed branch
#   pwsh -File tests/real-machine-test.ps1 -Only linux     # one host
[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot 'real-machine-hosts.json'),
  [string]$Ref,
  [string[]]$Only
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ConfigPath)) {
  throw "config not found: $ConfigPath`nCopy tests/real-machine-hosts.example.json to tests/real-machine-hosts.json and fill it in."
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$repo = $cfg.repo_url; if (-not $repo) { throw "config.repo_url is required" }
if (-not $Ref) { $Ref = if ($cfg.ref) { $cfg.ref } else { 'main' } }
$vaultDefault = if ($cfg.vault) { $cfg.vault } else { 'Personal' }

Import-Module Posh-SSH -ErrorAction Stop
if (-not (Get-Command op -ErrorAction SilentlyContinue)) { throw "1Password CLI 'op' not found on PATH" }

function New-HostCred($item, $vault) {
  $ua = (op read "op://$vault/$item/url") -replace '^[a-z]+://',''
  if (-not $ua) { throw "op could not read op://$vault/$item/url - unlock 1Password desktop integration" }
  $parts = $ua.Split('@', 2)
  $sec = (op read "op://$vault/$item/password") | ConvertTo-SecureString -AsPlainText -Force
  [pscustomobject]@{ User = $parts[0]; HostName = $parts[1]; Cred = [pscredential]::new($parts[0], $sec) }
}

function Invoke-Remote($sid, $command, $timeout = 180) {
  (Invoke-SSHCommand -SessionId $sid -Command $command -TimeOut $timeout).Output -join "`n"
}

# Pull the last "N passed, M failed" tally out of test output (handles bash and PS).
function Get-Tally($text) {
  $m = [regex]::Matches([string]$text, '\d+ passed, \d+ failed')
  if ($m.Count) { $m[$m.Count - 1].Value }
  else { 'NO RESULT: ' + (([string]$text -split "`n") | Where-Object { $_ } | Select-Object -Last 1) }
}

function Test-UnixHost($sid, $repo, $ref) {
  $clone = "D=`$(mktemp -d) && (git clone -q -b $ref $repo `$D 2>/dev/null || git clone -q $repo `$D) && cd `$D && echo READY:`$D"
  $out = Invoke-Remote $sid $clone 90
  if ($out -notmatch 'READY:(\S+)') { return @([pscustomobject]@{ Name = 'clone'; Result = "FAILED: $out" }) }
  $dir = $Matches[1]
  $suite = Get-Tally (Invoke-Remote $sid "cd $dir && bash tests/test_claudectl.sh 2>&1 | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -1")
  $smoke = Get-Tally (Invoke-Remote $sid "cd $dir && bash tests/smoke.sh 2>&1 | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -1")
  Invoke-Remote $sid "rm -rf $dir" 30 | Out-Null
  @(
    [pscustomobject]@{ Name = 'unit suite (bash)'; Result = $suite },
    [pscustomobject]@{ Name = 'smoke (bash)';      Result = $smoke }
  )
}

function Test-WindowsHost($sid, $repo, $ref) {
  $d = '%TEMP%\cctl-rmt-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  $clone = "git clone -q -b $ref $repo `"$d`" 2>nul || git clone -q $repo `"$d`" & if exist `"$d\scripts\claudectl.ps1`" (echo READY) else (echo CLONEFAIL)"
  if ((Invoke-Remote $sid $clone 120) -notmatch 'READY') { return @([pscustomobject]@{ Name = 'clone'; Result = 'FAILED' }) }
  $res = @()
  $res += [pscustomobject]@{ Name = 'unit suite (PS 5.1)'; Result = Get-Tally (Invoke-Remote $sid "powershell -NoProfile -ExecutionPolicy Bypass -File `"$d\tests\test_claudectl.ps1`" 2>&1") }
  if ((Invoke-SSHCommand -SessionId $sid -Command 'where pwsh' -TimeOut 20).ExitStatus -eq 0) {
    $res += [pscustomobject]@{ Name = 'unit suite (pwsh 7)'; Result = Get-Tally (Invoke-Remote $sid "pwsh -NoProfile -File `"$d\tests\test_claudectl.ps1`" 2>&1") }
  } else {
    $res += [pscustomobject]@{ Name = 'unit suite (pwsh 7)'; Result = 'SKIPPED (pwsh 7 not installed)' }
  }
  $res += [pscustomobject]@{ Name = 'smoke (PS 5.1)'; Result = Get-Tally (Invoke-Remote $sid "powershell -NoProfile -ExecutionPolicy Bypass -File `"$d\tests\smoke.ps1`" 2>&1") }
  Invoke-Remote $sid "powershell -NoProfile -Command `"Remove-Item -Recurse -Force '$d'`"" 30 | Out-Null
  $res
}

$report = [ordered]@{}
$anyFail = $false
foreach ($h in $cfg.hosts) {
  if ($Only -and ($Only -notcontains $h.name)) { continue }
  Write-Host "`n=== $($h.name) [$($h.type)] ===" -ForegroundColor Cyan
  $vault = if ($h.vault) { $h.vault } else { $vaultDefault }
  try {
    $hc = New-HostCred $h.op_item $vault
    $s = New-SSHSession -ComputerName $hc.HostName -Port 22 -Credential $hc.Cred -AcceptKey -ConnectionTimeout 25
    $rows = if ($h.type -eq 'windows') { Test-WindowsHost $s.SessionId $repo $Ref } else { Test-UnixHost $s.SessionId $repo $Ref }
    Remove-SSHSession -SessionId $s.SessionId | Out-Null
    foreach ($row in $rows) {
      $pass = $row.Result -match '^\s*\d+ passed, 0 failed\s*$'
      $skip = $row.Result -match 'SKIPPED'
      if (-not $pass -and -not $skip) { $anyFail = $true }
      Write-Host ("  {0,-22} {1}" -f $row.Name, $row.Result) -ForegroundColor $(if ($pass) { 'Green' } elseif ($skip) { 'Yellow' } else { 'Red' })
      $report["$($h.name) / $($row.Name)"] = $row.Result
    }
  } catch {
    $anyFail = $true
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $report["$($h.name)"] = "ERROR: $($_.Exception.Message)"
  }
}

Write-Host "`n===== SUMMARY =====" -ForegroundColor Cyan
$report.GetEnumerator() | ForEach-Object { "  {0,-40} {1}" -f $_.Key, $_.Value }
if ($anyFail) { Write-Host "`nRESULT: FAIL" -ForegroundColor Red; exit 1 }
Write-Host "`nRESULT: PASS" -ForegroundColor Green; exit 0
