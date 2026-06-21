# Changelog

## [0.2.3] — 2026-06-21

### Added

- **Real-machine test plan** — `tests/real-machine-test.ps1`, a generic, config-driven orchestrator
  that runs the full matrix (both unit suites + smoke; on Windows, **both** PowerShell 5.1 and pwsh 7)
  across real Linux, macOS, and Windows hosts over SSH. Credentials come from 1Password (read-only)
  into in-memory SecureStrings — never logged. Host specifics live in a gitignored
  `tests/real-machine-hosts.json` (template: `tests/real-machine-hosts.example.json`). See
  [docs/real-machine-testing.md](docs/real-machine-testing.md).
- `smoke.sh` now asserts **live `status` attribution** — a running `CLAUDE_CONFIG_DIR` process is
  tied to its instance via `/proc` on Linux, and the `/proc`-absent clean path is checked on macOS.

### Changed

- **The PowerShell unit suite now runs under both 5.1 and pwsh 7.** `test_claudectl.ps1` drives
  `claudectl.ps1` via the *same* interpreter that launches the suite (`$PSExe`), so
  `powershell -File ...` exercises 5.1 (the production `claudectl.cmd` path) and `pwsh -File ...`
  exercises 7. CI now runs the suite under both on `windows-latest`.

## [0.2.2] — 2026-06-21

### Fixed

- **Windows: `claudectl` failed to run under Windows PowerShell 5.1** — the production entry point
  (`claudectl.cmd`) invokes `claudectl.ps1` via `powershell` (5.1), which reads a BOM-less `.ps1` as
  Windows-1252; the non-ASCII em-dashes inside `Write-Host`/`Die` strings then broke parsing entirely
  (`MissingEndCurlyBrace`). CI never caught it because it only ran `pwsh` (7). `claudectl.ps1` is now
  pure ASCII, so it parses identically under PowerShell 5.1 and 7. Found via real-machine testing.

### Added

- **Real-machine smoke harness** `tests/smoke.{sh,ps1}` — a non-hermetic, real-`claude`-aware
  full-lifecycle check (still sandboxed via `CLAUDECTL_BASE`/`CLAUDECTL_BIN`), safe to run over SSH.
  Includes a security assertion that `token` never prints the credential value.
- **CI now exercises the Windows 5.1 production path** — a `windows-latest` step parse-checks
  `claudectl.ps1` and runs `smoke.ps1` under `powershell` (5.1), guarding the regression above.

### Changed

- The bash suite (`tests/test_claudectl.sh`) skips the `chmod 700` and `python3` JSON-schema
  assertions under Git Bash/MSYS (where they are spuriously red), keeping them on Linux/macOS CI.

## [0.2.1] — 2026-06-20

### Added

- Branch-level test coverage in both suites (`test_claudectl.sh`, `test_claudectl.ps1`), kept in parity:
  - Missing-name usage errors for all name-taking commands
  - `require_instance` / `Assert-Instance` failures on `reset`, `remove`, `config`, `token`, and `clone` source
  - `spawn` launcher-missing branch and the valid `--project` + `--dry-run` path
  - Dispatch aliases (`ls`, `rm`, `--version`, `--help`, `-h`) and bare-invocation default-to-help
  - `confirm` prompt behaviour — `n` aborts (config survives), `y` proceeds (bash-only; PowerShell
    `Read-Host` cannot reliably read redirected stdin)

## [0.2.0] — 2026-06-20

### Added

- `claudectl setup` now wires PATH for **fish** (`~/.config/fish/config.fish`, `set -gx` syntax) in
  addition to bash, zsh, and sh
- Hermetic `setup` tests in `test_claudectl.sh` (PATH wiring, idempotency, non-fatal-when-Claude-absent),
  isolated via `HOME` + `XDG_CONFIG_HOME` overrides

### Changed

- **PATH wiring is now a single implementation.** `setup.sh` and `setup.ps1` delegate to
  `claudectl setup` instead of each carrying their own copy
- `claudectl setup` wires PATH **before** checking for Claude Code, and only appends to shell rc files
  that already exist (never creates rc files for unused shells)
- Shell-agnostic activation hint ("reload your shell rc") replaces the bash-specific `source ~/.bashrc`

### Fixed

- `claudectl setup` no longer **exits 1** when Claude Code is absent — a missing binary is now an
  informational note, so PATH setup succeeds independently of Claude Code installation
  (behavior change; pre-1.0)
- `spawn` parity: PowerShell now **rejects an unknown flag** before `--` (`unknown spawn flag: …`,
  non-zero exit) instead of silently passing it through to `claude`, matching the bash interface

## [0.1.0] — 2026-06-19

### Added

- `claudectl add <name>` — create isolated instance with config dir + launcher
- `claudectl list [--json]` — list all instances including vanilla
- `claudectl path <name>` — print config directory
- `claudectl reset <name> [--force]` — wipe config dir, keep launcher
- `claudectl remove <name> [--purge] [--force]` — remove launcher (optionally config)
- `claudectl spawn <name> [--project] [--dry-run] [-- args]` — launch Claude Code
- `claudectl status [--json]` — show running instances
- `claudectl clone <src> <dst> [--deep]` — copy settings between instances
- `claudectl config <name> [key [val]]` — read/write settings.json
- `claudectl token <name>` — show credentials path and CI hint
- `claudectl version` — print claudectl + claude versions
- `claudectl setup [--update]` — verify install and configure PATH
- Physical integration tests (`test_claudectl.sh`, `test_claudectl.ps1`)
- GitHub Actions CI (Linux + macOS + Windows)
- `CLAUDECTL_BASE` and `CLAUDECTL_BIN` env var overrides for test isolation
- Cross-platform: bash (Linux/macOS) + PowerShell (Windows)
