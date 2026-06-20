# Contributing

## Setup

```bash
git clone https://github.com/A-H-911/claudectl.git
cd claudectl
bash tests/test_claudectl.sh
```

## Branching & merging

`main` is a **protected branch** — every change lands via pull request, maintainers included:

- **No direct pushes** to `main`; force-pushes and branch deletion are blocked.
- **CI must pass** on all three jobs before merge: `Test (Linux)`, `Test (macOS)`, `Test (Windows)`.
- The branch must be **up to date** with `main` before merging.
- **Linear history** is enforced — merge with **squash** or **rebase** (no merge commits).
- Reviews are not required, so you can self-merge once CI is green.

Typical flow:

```bash
git checkout -b feat/my-change
bash tests/test_claudectl.sh          # verify locally
pwsh -File tests/test_claudectl.ps1
git push -u origin feat/my-change
gh pr create --fill                   # CI runs on all 3 platforms
gh pr merge --squash --delete-branch  # after CI is green
```

## Adding a command

1. `cmd_<name>()` + `help_<name>()` in `scripts/claudectl`
2. Add to `case` dispatch at bottom
3. Mirror in `scripts/claudectl.ps1`
4. Add tests in both test files
5. Document in `docs/commands.md`

## Testing `setup`

The bash suite tests `setup` hermetically by redirecting `HOME` + `XDG_CONFIG_HOME` to a temp dir, so
real shell rc files are never touched. The **PowerShell** `setup` writes the user PATH via the Windows
registry, which cannot be redirected the way `HOME` can — so the PS suite intentionally covers only
`help setup` (not a live `setup` run) to keep tests from mutating the runner's environment. The shared
PATH-wiring logic shape is covered by the hermetic bash test.

## PR checklist

- [ ] `bash tests/test_claudectl.sh` passes
- [ ] `pwsh -File tests/test_claudectl.ps1` passes
- [ ] CI green on Linux, macOS, and Windows (enforced by branch protection before merge)
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
