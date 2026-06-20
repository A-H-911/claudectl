# Changelog

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
