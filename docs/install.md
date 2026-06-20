# Installation

## Prerequisites

> **claudectl manages Claude Code instances, but Claude Code itself must be installed first.**
>
> Install Claude Code: https://claude.ai/download
>
> After installing, verify: `claude --version`

## Linux / macOS

### One-liner (recommended)

```bash
git clone https://github.com/A-H-911/claudectl.git
cd claudectl
bash setup.sh
```

### Manual

```bash
mkdir -p ~/.local/bin
cp scripts/claudectl ~/.local/bin/claudectl
chmod +x ~/.local/bin/claudectl
```

Add to your shell's rc file:

```bash
# bash (~/.bashrc), zsh (~/.zshrc), sh (~/.profile)
export PATH="$HOME/.local/bin:$PATH"
```

```fish
# fish (~/.config/fish/config.fish)
set -gx PATH "$HOME/.local/bin" $PATH
```

Then open a new terminal, or reload your shell rc (e.g. `source ~/.bashrc`).

> `bash setup.sh` (or `claudectl setup`) does all of this automatically for bash, zsh, sh, and fish —
> it only edits rc files that already exist.

### Verify

```bash
claudectl version
claudectl help
```

## Windows

### One-liner (PowerShell, recommended)

```powershell
git clone https://github.com/A-H-911/claudectl.git
cd claudectl
.\setup.ps1
```

If you get an execution policy error:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\setup.ps1
```

### Manual

```powershell
$bin = "$env:USERPROFILE\.local\bin"
New-Item -ItemType Directory $bin -Force | Out-Null
Copy-Item scripts\claudectl.ps1 "$bin\claudectl.ps1"
Copy-Item scripts\claudectl.cmd "$bin\claudectl.cmd"
```

Add `%USERPROFILE%\.local\bin` to your user PATH via System Properties > Environment Variables.

### Verify

```powershell
claudectl version
claudectl help
```

## CI / Server (non-interactive)

```bash
export CLAUDECTL_BASE=/var/lib/claude-instances
export CLAUDECTL_BIN=/usr/local/bin
export CLAUDE_CODE_OAUTH_TOKEN=<token from claudectl token <name>>

claudectl add ci
claudectl spawn ci -- --bare -p "<prompt>"
```

See `claudectl token` for extracting OAuth tokens.

## Updating claudectl

```bash
claudectl setup --update
```

Requires `curl`. Self-replaces the script from `$CLAUDECTL_UPDATE_URL`.

## Uninstalling

```bash
rm ~/.local/bin/claudectl
rm ~/.local/bin/claude-*
rm -rf ~/.claude-instances   # WARNING: permanent
```
