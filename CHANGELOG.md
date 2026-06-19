# Changelog

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
