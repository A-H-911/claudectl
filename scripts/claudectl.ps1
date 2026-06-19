#!/usr/bin/env pwsh
# claudectl.ps1 — manage isolated Claude Code instances (Windows PowerShell)
# https://github.com/A-H-911/claudectl  ← update this when forking

$VERSION = "0.1.0"
$CLAUDECTL_UPDATE_URL = if ($env:CLAUDECTL_UPDATE_URL) { $env:CLAUDECTL_UPDATE_URL } else { "https://raw.githubusercontent.com/A-H-911/claudectl/main/scripts/claudectl.ps1" }
$BASE = if ($env:CLAUDECTL_BASE) { $env:CLAUDECTL_BASE } else { "$env:USERPROFILE\.claude-instances" }
$BIN  = if ($env:CLAUDECTL_BIN)  { $env:CLAUDECTL_BIN  } else { "$env:USERPROFILE\.local\bin" }

# ── Utilities ────────────────────────────────────────────────────────────────

function Die {
    param([string]$msg)
    Write-Error "error: $msg"
    exit 1
}

function Confirm-Prompt {
    param([string]$msg, [switch]$Force)
    if ($Force) { return }
    $reply = Read-Host "$msg [y/N]"
    if ($reply -notmatch '^[Yy]$') { Die "aborted" }
}

function Assert-Instance {
    param([string]$name)
    if ($name -eq "vanilla") { return }
    if (-not (Test-Path "$BASE\$name" -PathType Container)) {
        Die "instance '$name' not found — run 'claudectl list' to see available instances"
    }
}

function Test-ValidName {
    param([string]$name)
    if ($name -notmatch '^[a-zA-Z0-9][-a-zA-Z0-9_]*$') {
        Die "invalid name '$name' — use letters, numbers, hyphens, underscores only (no spaces)"
    }
}

# ── cmd_add ──────────────────────────────────────────────────────────────────

function cmd_add {
    param([string]$name = "", [switch]$Force)
    if (-not $name) { Die "usage: claudectl add <name> [--force]" }
    Test-ValidName $name
    $dir      = "$BASE\$name"
    $launcher = "$BIN\claude-$name.cmd"

    if ((Test-Path $dir -PathType Container) -and (-not $Force)) {
        Die "instance '$name' already exists — use --force to reinitialise"
    }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    icacls $dir /inheritance:d /grant:r "${env:USERNAME}:(OI)(CI)F" 2>$null | Out-Null

    # Launcher expands $dir and $BIN at creation time — CLAUDECTL_BIN override works in tests
    $launcherContent = "@echo off`r`nsetlocal`r`nset CLAUDE_CONFIG_DIR=$dir`r`n`"$BIN\claude.exe`" %*"
    Set-Content -Path $launcher -Value $launcherContent -Encoding ascii

    Write-Host "created instance `"$name`""
    Write-Host "  config  : $dir"
    Write-Host "  command : claude-$name"
    Write-Host "  next    : run ``claude-$name``, then complete /login"
}

# ── cmd_list ─────────────────────────────────────────────────────────────────

function cmd_list {
    param([switch]$Json)
    $credVanilla  = "$env:USERPROFILE\.claude\.credentials.json"
    $loggedVanilla = Test-Path $credVanilla

    if ($Json) {
        $items = @()
        $items += [ordered]@{
            name       = "vanilla"
            config_dir = "$env:USERPROFILE\.claude"
            logged_in  = $loggedVanilla
        }
        if (Test-Path $BASE -PathType Container) {
            Get-ChildItem $BASE -Directory | ForEach-Object {
                $n    = $_.Name
                $cred = "$BASE\$n\.credentials.json"
                $items += [ordered]@{
                    name       = $n
                    config_dir = $_.FullName
                    logged_in  = (Test-Path $cred)
                }
            }
        }
        $items | ConvertTo-Json -Depth 3
    } else {
        "{0,-16}  {1,-50}  {2}" -f "NAME","CONFIG_DIR","LOGGED_IN" | Write-Host
        "{0,-16}  {1,-50}  {2}" -f "vanilla","$env:USERPROFILE\.claude",$(if ($loggedVanilla){"yes"}else{"no"}) | Write-Host
        if (Test-Path $BASE -PathType Container) {
            Get-ChildItem $BASE -Directory | ForEach-Object {
                $n      = $_.Name
                $logged = if (Test-Path "$BASE\$n\.credentials.json") {"yes"} else {"no"}
                "{0,-16}  {1,-50}  {2}" -f $n,$_.FullName,$logged | Write-Host
            }
        }
    }
}

# ── cmd_path ─────────────────────────────────────────────────────────────────

function cmd_path {
    param([string]$name = "")
    if (-not $name) { Die "usage: claudectl path <name>" }
    if ($name -eq "vanilla") {
        Write-Host "$env:USERPROFILE\.claude"
    } else {
        Assert-Instance $name
        Write-Host "$BASE\$name"
    }
}

# ── cmd_reset ────────────────────────────────────────────────────────────────

function cmd_reset {
    param([string]$name = "", [switch]$Force)
    if (-not $name) { Die "usage: claudectl reset <name> [--force]" }
    if ($name -eq "vanilla") { Die "cannot reset the vanilla instance" }
    Assert-Instance $name
    $dir = "$BASE\$name"
    Confirm-Prompt "wipe all config in '$name'? this cannot be undone" -Force:$Force
    Remove-Item -Path $dir -Recurse -Force
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    icacls $dir /inheritance:d /grant:r "${env:USERNAME}:(OI)(CI)F" 2>$null | Out-Null
    Write-Host "reset instance `"$name`" — config dir wiped, launcher kept"
}

# ── cmd_remove ───────────────────────────────────────────────────────────────

function cmd_remove {
    param([string]$name = "", [switch]$Purge, [switch]$Force)
    if (-not $name) { Die "usage: claudectl remove <name> [--purge] [--force]" }
    if ($name -eq "vanilla") { Die "cannot remove the vanilla instance" }
    Assert-Instance $name
    $dir      = "$BASE\$name"
    $launcher = "$BIN\claude-$name.cmd"

    if ($Purge) {
        Confirm-Prompt "permanently remove launcher AND config for '$name'?" -Force:$Force
        if (Test-Path $launcher) { Remove-Item $launcher -Force }
        Remove-Item -Path $dir -Recurse -Force
        Write-Host "removed launcher and config for `"$name`""
    } else {
        Confirm-Prompt "remove launcher for '$name'? (config dir kept)" -Force:$Force
        if (Test-Path $launcher) { Remove-Item $launcher -Force }
        Write-Host "removed launcher for `"$name`" (config dir kept at $dir)"
        Write-Host "use --purge to also remove the config directory"
    }
}

# ── cmd_spawn ────────────────────────────────────────────────────────────────

function cmd_spawn {
    param([string]$name = "", [string]$Project = "", [switch]$DryRun, [string[]]$ClaudeArgs = @())
    if (-not $name) { Die "usage: claudectl spawn <name> [--project <dir>] [--dry-run] [-- <claude-args>...]" }
    Assert-Instance $name
    $launcher = "$BIN\claude-$name.cmd"
    if (-not (Test-Path $launcher)) { Die "launcher '$launcher' not found — run 'claudectl add $name' again" }

    if ($Project) {
        if (-not (Test-Path $Project -PathType Container)) { Die "project directory '$Project' not found" }
        Push-Location $Project
    }

    if ($DryRun) {
        if ($ClaudeArgs.Count -gt 0) {
            Write-Host "$launcher $($ClaudeArgs -join ' ')"
        } else {
            Write-Host $launcher
        }
        if ($Project) { Pop-Location }
        return
    }

    if ($ClaudeArgs.Count -gt 0) {
        & $launcher @ClaudeArgs
    } else {
        & $launcher
    }
    $code = $LASTEXITCODE
    if ($Project) { Pop-Location }
    exit $code
}

# ── cmd_status ───────────────────────────────────────────────────────────────

function cmd_status {
    param([switch]$Json)
    $processes = Get-Process "claude*" -ErrorAction SilentlyContinue

    if ($Json) {
        $items = if ($processes) {
            $processes | ForEach-Object {
                [ordered]@{ pid = $_.Id; instance = "<unknown>"; config_dir = "" }
            }
        } else { @() }
        $items | ConvertTo-Json -Depth 3
    } else {
        if (-not $processes) {
            Write-Host "no Claude instances currently running"
            return
        }
        "{0,-8}  {1,-30}" -f "PID","STARTED" | Write-Host
        $processes | ForEach-Object {
            "{0,-8}  {1,-30}" -f $_.Id,$_.StartTime | Write-Host
        }
        Write-Host ""
        Write-Host "Note: per-instance attribution requires Linux /proc. On Windows, check CLAUDE_CONFIG_DIR in process env manually."
    }
}

# ── cmd_clone ────────────────────────────────────────────────────────────────

function cmd_clone {
    param([string]$src = "", [string]$dst = "", [switch]$Deep)
    if (-not $src -or -not $dst) { Die "usage: claudectl clone <src> <dst> [--deep]" }
    Assert-Instance $src
    Assert-Instance $dst

    $srcDir = if ($src -eq "vanilla") { "$env:USERPROFILE\.claude" } else { "$BASE\$src" }
    $dstDir = if ($dst -eq "vanilla") { "$env:USERPROFILE\.claude" } else { "$BASE\$dst" }

    # These are NEVER copied — auth tokens and auto-generated state
    $denylist = @(".credentials.json","cache","backups","sessions","history.jsonl","telemetry","usage-data","mcp-needs-auth-cache.json")

    if ($Deep) {
        Get-ChildItem $srcDir -Force | Where-Object { $denylist -notcontains $_.Name } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $dstDir -Recurse -Force
        }
        Write-Host "deep-cloned `"$src`" -> `"$dst`" (credentials and cache excluded)"
    } else {
        $settingsFile = "$srcDir\settings.json"
        if (Test-Path $settingsFile) {
            Copy-Item $settingsFile "$dstDir\settings.json" -Force
            Write-Host "cloned settings.json from `"$src`" -> `"$dst`""
        } else {
            Write-Host "note: `"$src`" has no settings.json yet — nothing to clone"
        }
    }
}

# ── cmd_config ───────────────────────────────────────────────────────────────

function cmd_config {
    param([string]$name = "", [string]$key = "", [string]$val = "")
    if (-not $name) { Die "usage: claudectl config <name> [<key> [<value>]]" }
    Assert-Instance $name
    $dir      = if ($name -eq "vanilla") { "$env:USERPROFILE\.claude" } else { "$BASE\$name" }
    $settings = "$dir\settings.json"

    if (-not $key) {
        if (Test-Path $settings) { Get-Content $settings | Write-Host } else { Write-Host "{}" }
        return
    }

    if (-not $val) {
        if (-not (Test-Path $settings)) { Write-Host ""; return }
        $data = Get-Content $settings -Raw | ConvertFrom-Json
        Write-Host $data.$key
        return
    }

    $data = if (Test-Path $settings) {
        Get-Content $settings -Raw | ConvertFrom-Json
    } else {
        [PSCustomObject]@{}
    }

    if ($data | Get-Member -Name $key -MemberType NoteProperty -ErrorAction SilentlyContinue) {
        $data.$key = $val
    } else {
        $data | Add-Member -MemberType NoteProperty -Name $key -Value $val
    }
    $data | ConvertTo-Json -Depth 10 | Set-Content $settings -Encoding utf8
    Write-Host "set $key = $val in `"$name`""
}

# ── cmd_token ────────────────────────────────────────────────────────────────

function cmd_token {
    param([string]$name = "")
    if (-not $name) { Die "usage: claudectl token <name>" }
    Assert-Instance $name
    $dir   = if ($name -eq "vanilla") { "$env:USERPROFILE\.claude" } else { "$BASE\$name" }
    $creds = "$dir\.credentials.json"

    if (-not (Test-Path $creds)) {
        Write-Error "instance '$name' has not completed /login"
        Write-Error "run ``claude-$name``, then complete /login inside Claude Code"
        exit 1
    }

    Write-Host "credentials: $creds"
    Write-Host "CI usage:    `$env:CLAUDE_CODE_OAUTH_TOKEN = (Get-Content '$creds' | ConvertFrom-Json).oauthToken"
}

# ── cmd_version ──────────────────────────────────────────────────────────────

function cmd_version {
    Write-Host "claudectl $VERSION"
    $claudeBin = "$BIN\claude.exe"
    if (Test-Path $claudeBin) {
        try { & $claudeBin --version 2>$null } catch {}
    } elseif (Get-Command claude -ErrorAction SilentlyContinue) {
        try { claude --version 2>$null } catch {}
    }
}

# ── cmd_setup ────────────────────────────────────────────────────────────────

function cmd_setup {
    param([switch]$Update)

    if ($Update) {
        $tmp = [System.IO.Path]::GetTempFileName() + ".ps1"
        Write-Host "downloading latest claudectl.ps1..."
        try {
            Invoke-WebRequest -Uri $CLAUDECTL_UPDATE_URL -OutFile $tmp -UseBasicParsing
        } catch {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Die "update download failed: $_"
        }
        $scriptPath = $MyInvocation.PSCommandPath
        Copy-Item $tmp $scriptPath -Force
        Remove-Item $tmp -Force
        Write-Host "updated to version: $(pwsh -File `"$scriptPath`" version)"
        return
    }

    $claudeBin = "$BIN\claude.exe"
    if (-not (Test-Path $claudeBin) -and -not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Host "Claude Code is not installed."
        Write-Host "Install it from: https://claude.ai/download"
        Write-Host "Then re-run: claudectl setup"
        exit 1
    }
    $found = if (Test-Path $claudeBin) { $claudeBin } else { (Get-Command claude).Source }
    Write-Host "claude binary: $found"

    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$BIN*") {
        Write-Host "adding $BIN to user PATH..."
        [Environment]::SetEnvironmentVariable("PATH", "$BIN;$userPath", "User")
        Write-Host "done — open a new terminal to activate"
    } else {
        Write-Host "PATH already includes $BIN"
    }

    Write-Host ""
    Write-Host "claudectl $VERSION is ready"
    Write-Host "Note: if execution policy blocks scripts, run:"
    Write-Host "  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
}

# ── Help ─────────────────────────────────────────────────────────────────────

function cmd_help {
    param([string]$sub = "")
    if ($sub) {
        switch ($sub) {
            "add"     { Write-Host "claudectl add <name> [--force]`nCreate isolated instance. Name: letters, numbers, hyphens, underscores only." }
            "list"    { Write-Host "claudectl list [--json]`nList all instances. vanilla = %USERPROFILE%\.claude.`n--json: array with name/config_dir/logged_in (bool)" }
            "path"    { Write-Host "claudectl path <name>`nPrint config dir. 'path vanilla' = %USERPROFILE%\.claude" }
            "reset"   { Write-Host "claudectl reset <name> [--force]`nWipe config dir, keep launcher. Cannot reset vanilla." }
            "remove"  { Write-Host "claudectl remove <name> [--purge] [--force]`nRemove launcher. --purge also removes config dir." }
            "spawn"   { Write-Host "claudectl spawn <name> [--project <dir>] [--dry-run] [-- <args>...]`nLaunch Claude Code. --dry-run prints command." }
            "status"  { Write-Host "claudectl status [--json]`nShow running Claude instances." }
            "clone"   { Write-Host "claudectl clone <src> <dst> [--deep]`nCopy settings.json (default) or all config except credentials (--deep)." }
            "config"  { Write-Host "claudectl config <name> [<key> [<value>]]`nRead/write settings.json." }
            "token"   { Write-Host "claudectl token <name>`nShow credentials path and CI hint. Exits 1 if not logged in." }
            "version" { Write-Host "claudectl version`nPrint claudectl + claude versions." }
            "setup"   { Write-Host "claudectl setup [--update]`nVerify install, configure PATH. --update: download latest." }
            default   { Die "unknown command '$sub'" }
        }
        return
    }
    Write-Host @"
claudectl $VERSION — manage isolated Claude Code instances

usage: claudectl <command> [options]

commands:
  add <name>              create a new isolated instance
  list                    list all instances
  path <name>             print config directory path
  reset <name>            wipe instance config (keep launcher)
  remove <name>           remove instance launcher [--purge removes config too]
  spawn <name>            launch Claude Code for an instance
  status                  show running Claude instances
  clone <src> <dst>       copy settings between instances
  config <name>           read/write instance settings.json
  token <name>            show credentials path and CI usage
  version                 show claudectl and claude version
  setup                   verify install and configure PATH

run 'claudectl help <command>' for detailed help on any command

environment:
  CLAUDECTL_BASE          instance storage root (default: %USERPROFILE%\.claude-instances)
  CLAUDECTL_BIN           binary/launcher dir (default: %USERPROFILE%\.local\bin)
  CLAUDECTL_UPDATE_URL    self-update source URL
"@
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

# Cast $args to a typed string array immediately so that range-slicing
# never unboxes a single-element result to a scalar string.
[string[]]$_argv = @($args | ForEach-Object { [string]$_ })
[Console]::Error.WriteLine("DIAG: args.Count=$($args.Count) argv=$($_argv -join '|') argv.GetType=$($_argv.GetType().Name)")
$cmd  = if ($_argv.Count -gt 0) { $_argv[0] } else { "help" }
[string[]]$rest = if ($_argv.Count -gt 1) { $_argv[1..($_argv.Count - 1)] } else { @() }
[Console]::Error.WriteLine("DIAG: cmd='$cmd' rest.Count=$($rest.Count) rest.GetType=$($rest.GetType().Name) rest0='$($rest[0])'")


switch ($cmd) {
    "add" {
        $force = $rest -contains "--force"
        $name  = $rest | Where-Object { $_ -ne "--force" } | Select-Object -First 1
        cmd_add -name "$name" -Force:$force
    }
    { $_ -in "list","ls" } {
        cmd_list -Json:($rest -contains "--json")
    }
    "path" {
        cmd_path -name ($rest | Select-Object -First 1)
    }
    "reset" {
        $force = $rest -contains "--force"
        $name  = $rest | Where-Object { $_ -ne "--force" } | Select-Object -First 1
        cmd_reset -name "$name" -Force:$force
    }
    { $_ -in "remove","rm" } {
        $purge = $rest -contains "--purge"
        $force = $rest -contains "--force" -or $rest -contains "-y"
        $name  = $rest | Where-Object { $_ -notin @("--purge","--force","-y") } | Select-Object -First 1
        cmd_remove -name "$name" -Purge:$purge -Force:$force
    }
    "spawn" {
        $project   = ""
        $dryRun    = $false
        $name      = ""
        $extraArgs = @()
        $seenDash  = $false
        $i = 0
        while ($i -lt $rest.Count) {
            if ($seenDash)               { $extraArgs += $rest[$i]; $i++ }
            elseif ($rest[$i] -eq "--") { $seenDash = $true; $i++ }
            elseif ($rest[$i] -eq "--project") { $project = $rest[$i+1]; $i += 2 }
            elseif ($rest[$i] -eq "--dry-run") { $dryRun = $true; $i++ }
            elseif (-not $name)         { $name = $rest[$i]; $i++ }
            else                        { $extraArgs += $rest[$i]; $i++ }
        }
        cmd_spawn -name "$name" -Project "$project" -DryRun:$dryRun -ClaudeArgs $extraArgs
    }
    "status" {
        cmd_status -Json:($rest -contains "--json")
    }
    "clone" {
        $deep      = $rest -contains "--deep"
        $positional = $rest | Where-Object { $_ -ne "--deep" }
        $src = if ($positional.Count -gt 0) { $positional[0] } else { "" }
        $dst = if ($positional.Count -gt 1) { $positional[1] } else { "" }
        cmd_clone -src "$src" -dst "$dst" -Deep:$deep
    }
    "config" {
        $n = if ($rest.Count -gt 0) { $rest[0] } else { "" }
        $k = if ($rest.Count -gt 1) { $rest[1] } else { "" }
        $v = if ($rest.Count -gt 2) { $rest[2] } else { "" }
        cmd_config -name "$n" -key "$k" -val "$v"
    }
    "token" {
        cmd_token -name ($rest | Select-Object -First 1)
    }
    { $_ -in "version","--version" } {
        cmd_version
    }
    "setup" {
        cmd_setup -Update:($rest -contains "--update")
    }
    { $_ -in "help","--help","-h" } {
        cmd_help -sub ($rest | Select-Object -First 1)
    }
    default {
        Write-Error "error: unknown command `"$cmd`""
        cmd_help
        exit 2
    }
}
