# Contributing

## Setup

```bash
git clone https://github.com/A-H-911/claudectl.git
cd claudectl
bash tests/test_claudectl.sh
```

## Adding a command

1. `cmd_<name>()` + `help_<name>()` in `scripts/claudectl`
2. Add to `case` dispatch at bottom
3. Mirror in `scripts/claudectl.ps1`
4. Add tests in both test files
5. Document in `docs/commands.md`

## PR checklist

- [ ] `bash tests/test_claudectl.sh` passes
- [ ] `pwsh -File tests/test_claudectl.ps1` passes
- [ ] No personal/org references inside functions (constants block only)
- [ ] `.credentials.json` denylist in `clone` unchanged
- [ ] Launcher template uses expanded `$BIN` (heredoc `<<EOF` not `<<'EOF'`)
- [ ] `CHANGELOG.md` updated

## Commit format

```
feat: add <command>
fix: handle missing settings.json in config
docs: update platform-notes for macOS
test: add token logged-out assertion
```

## Issues

https://github.com/A-H-911/claudectl/issues — include OS, shell version, `claudectl version` output, and reproduction steps.
