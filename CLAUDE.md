# CLAUDE.md — Developer Guide

This file provides guidance when working with the claudectl codebase.

## What this repo is

claudectl is a cross-platform terminal CLI (bash + PowerShell) for managing isolated Claude Code
instances via `CLAUDE_CONFIG_DIR`. It is a standalone shell script — no build step, no dependencies
beyond bash/python3/jq.

## Test commands

```bash
# Run bash integration tests (safe — uses temp dir, never touches real ~/.claude-instances)
bash tests/test_claudectl.sh

# Run PowerShell integration tests (Windows)
pwsh -File tests/test_claudectl.ps1

# Smoke test the bash CLI
bash scripts/claudectl help
bash scripts/claudectl version
```

## Environment variables for testing

```bash
export CLAUDECTL_BASE=/tmp/test-instances   # redirect instance storage
export CLAUDECTL_BIN=/tmp/test-bin          # redirect launcher install dir
```

The test suite sets these automatically. Use them manually to avoid touching your real
`~/.claude-instances` or `~/.local/bin` during development.

## How to add a new command

1. Add `cmd_<name>()` in `scripts/claudectl`
2. Add `help_<name>()` with usage, flags, and examples
3. Add to the `case` dispatch at the bottom
4. Mirror in `scripts/claudectl.ps1`
5. Add tests in `tests/test_claudectl.sh` and `tests/test_claudectl.ps1`
6. Document in `docs/commands.md`

## Invariants

1. **Generic scripts**: Constants block at top only; functions have zero personal/org references
2. **No credential copy**: `clone` denylist guards `.credentials.json` — never remove this
3. **Test isolation**: Tests NEVER touch real `~/.claude-instances` or `~/.local/bin`
4. **CLAUDECTL_BIN expansion**: Launcher heredoc must be `<<EOF` (unquoted) to expand `$BIN` at creation time — this is what makes `CLAUDECTL_BIN` overrides work in tests
5. **Cross-platform parity**: Every bash command has a PowerShell equivalent with identical interface
6. **`spawn --dry-run`**: Always prints command; never executes — required for testability
7. **`config` handles missing files**: Returns `{}` for empty instance; creates file on write
8. **Name validation**: `^[a-zA-Z0-9][-a-zA-Z0-9_]*$` — spaces break Windows batch launchers

## Versioning

- New commands or flags: MINOR (`0.2.0`)
- Changed command interface: MAJOR (`1.0.0`)
- Bug fixes: PATCH (`0.1.1`)

Update `VERSION=` in `scripts/claudectl`, `$VERSION =` in `scripts/claudectl.ps1`, and `CHANGELOG.md`.

## Forks

Update the top-of-file URL comment and `CLAUDECTL_UPDATE_URL` default in both scripts.
All other behavior is inherited from `CLAUDECTL_BASE` and `CLAUDECTL_BIN` env vars.
