# CLAUDE.md — Developer Guide

This file provides guidance when working with the claudectl codebase.

## What this repo is

claudectl is a cross-platform terminal CLI (bash + PowerShell) for managing isolated Claude Code
instances via `CLAUDE_CONFIG_DIR`. It is a standalone shell script — no build step, no dependencies
beyond bash/python3/jq.

## Repository layout

Lightweight monorepo. Future tools go under `packages/<name>/` (see [packages/README.md](packages/README.md)).
The `claudectl` CLI deliberately stays at the root — `scripts/claudectl*`, `setup.{sh,ps1}`, `tests/` —
because its self-update URL (`CLAUDECTL_UPDATE_URL`) is pinned to `…/main/scripts/claudectl[.ps1]`;
moving it would break `setup --update` for existing installs. Doc images live in `docs/assets/`.

## Architecture (the one mental model)

`add <name>` creates two things: a config dir `$CLAUDECTL_BASE/<name>/` (chmod 700) and a launcher
`$CLAUDECTL_BIN/claude-<name>` that does `export CLAUDE_CONFIG_DIR=<dir>` then `exec`s the real
`claude`. **The launcher is the entire isolation mechanism** — every instance is just a separate
`CLAUDE_CONFIG_DIR`. `spawn` (and the launcher itself) are the only things that start Claude Code;
all other commands (`list`, `clone`, `config`, `token`, `reset`, `remove`, `status`) only inspect
or manipulate those config dirs.

- `vanilla` is a virtual instance = `~/.claude` (default config). It cannot be reset or removed.
- `status` attributes running PIDs to instances by reading `/proc/*/environ` on Linux/macOS;
  Windows uses `Get-Process` and cannot do per-instance attribution.
- PATH wiring lives in **one** place per platform: `configure_path()` in `scripts/claudectl`
  (bash; covers bash/zsh/sh/fish, editing only rc files that already exist) and the PATH block in
  `cmd_setup` (`scripts/claudectl.ps1`, registry). `setup.sh`/`setup.ps1` are thin installers that
  copy the script and then **delegate** to `claudectl setup` — never duplicate the PATH logic there.
  `setup` is non-fatal when Claude Code is absent (it wires PATH regardless, then notes the binary).

## Test commands

```bash
# Run bash integration tests (safe — uses temp dir, never touches real ~/.claude-instances)
bash tests/test_claudectl.sh

# Run PowerShell integration tests (Windows) — under BOTH 5.1 and pwsh 7:
powershell -File tests/test_claudectl.ps1   # Windows PowerShell 5.1 (production claudectl.cmd path)
pwsh       -File tests/test_claudectl.ps1   # pwsh 7

# Real-machine end-to-end smoke (sandboxed; safe over SSH)
bash       tests/smoke.sh                    # Linux/macOS
powershell -File tests/smoke.ps1             # Windows

# Smoke test the bash CLI
bash scripts/claudectl help
bash scripts/claudectl version
```

**Real-machine test plan (run on every change):** the hermetic suites don't cover real-OS behavior —
Linux `/proc` attribution, macOS bash 3.2 / BSD utils, and Windows PowerShell 5.1 (the production
`claudectl.cmd` path). `tests/real-machine-test.ps1` runs the full matrix (both suites + smoke, both
PowerShell versions on Windows) on real Linux, macOS, and Windows hosts over SSH. See
[docs/real-machine-testing.md](docs/real-machine-testing.md).

The suites are **monolithic shell scripts** (no test framework, no `--filter`). To run one case,
temporarily comment out the others or copy the block into a scratch script. Both suites are
hermetic: they create a temp dir, point `CLAUDECTL_BASE`/`CLAUDECTL_BIN` at it, and install
`tests/helpers/fake-claude` as a stub `claude` binary so `spawn`/`version` never invoke the real
Claude Code. CI (`.github/workflows/ci.yml`) runs the bash suite on Linux + macOS and the
PowerShell suite on Windows — keep all three green.

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

`scripts/claudectl.cmd` is a pure pass-through to `.ps1` (`powershell -File ... %*`) — never edit
it per-command.

## Branching & CI

`main` is a **protected branch — you cannot push to it directly.** Land every change via PR:

1. Branch, commit, push.
2. Open a PR (`gh pr create --fill`); CI runs the bash suite on Linux + macOS and the PowerShell
   suite on Windows.
3. Merge with **squash** or **rebase** once all three checks are green — linear history is enforced
   (merge commits are rejected). 0 approvals are required, so you can self-merge.

Force-pushes and branch deletion on `main` are blocked, and the rules apply to admins too. There is
no direct-push escape hatch — even a one-line fix goes through a (fast, ~40s) PR.

## Invariants

1. **Generic scripts**: Constants block at top only; functions have zero personal/org references
2. **No credential copy**: `clone` denylist guards `.credentials.json` — never remove this
3. **Test isolation**: Tests NEVER touch real `~/.claude-instances` or `~/.local/bin`
4. **CLAUDECTL_BIN expansion**: Launcher heredoc must be `<<EOF` (unquoted) to expand `$BIN` at creation time — this is what makes `CLAUDECTL_BIN` overrides work in tests
5. **Cross-platform parity**: Every bash command has a PowerShell equivalent with identical interface
6. **`spawn --dry-run`**: Always prints command; never executes — required for testability
7. **`config` handles missing files**: Returns `{}` for empty instance; creates file on write
8. **Name validation**: `^[a-zA-Z0-9][-a-zA-Z0-9_]*$` — spaces break Windows batch launchers
9. **Self-update path pin**: never relocate `scripts/claudectl*` — `CLAUDECTL_UPDATE_URL` is pinned to that path; moving it breaks `setup --update` for existing installs (see Repository layout)

## Versioning

- New commands or flags: MINOR (`0.2.0`)
- Changed command interface: MAJOR (`1.0.0`)
- Bug fixes: PATCH (`0.1.1`)

Update `VERSION=` in `scripts/claudectl`, `$VERSION =` in `scripts/claudectl.ps1`, and `CHANGELOG.md`.

## Forks

Update the top-of-file URL comment and `CLAUDECTL_UPDATE_URL` default in both scripts.
All other behavior is inherited from `CLAUDECTL_BASE` and `CLAUDECTL_BIN` env vars.
