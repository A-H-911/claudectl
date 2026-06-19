# Platform Notes

## Cross-Platform Differences

| Feature | Linux | macOS | Windows |
|---------|-------|-------|---------|
| Claude binary | `claude` | `claude` | `claude.exe` |
| claudectl | `claudectl` | `claudectl` | `claudectl.cmd` |
| Launchers | `claude-<name>` shell scripts | `claude-<name>` shell scripts | `claude-<name>.cmd` batch files |
| Instance base | `~/.claude-instances/` | `~/.claude-instances/` | `%USERPROFILE%\.claude-instances\` |
| `spawn` exec model | `exec` (process replacement) | `exec` (process replacement) | `& cmd; exit $code` |
| `status` attribution | Full via `/proc/*/environ` | No `/proc` — not available | PID + start time only |
| Permissions | `chmod 700` | `chmod 700` | `icacls` ACL restriction |

## Linux

`status` reads `/proc/*/environ` for any process owned by the current user. This provides full
per-instance attribution without root.

`spawn` uses `exec` — the claudectl process is replaced by Claude. When Claude exits, you return to
the terminal that launched claudectl.

## macOS

Same bash script as Linux. `status` does not work on macOS (no `/proc`); it exits 0 with a
"no instances currently running" message.

`stat -c%a` (GNU) is not available on macOS. The test suite uses `python3` for permission checks
to avoid this incompatibility.

`realpath` is not available by default on macOS. The `setup --update` command uses portable path
resolution instead:
```bash
case "$script_path" in
  /*) ;;
  *) script_path="$(cd "$(dirname "$script_path")" && pwd)/$(basename "$script_path")";;
esac
```

## Windows

Launchers are `.cmd` batch files:
```batch
@echo off
setlocal
set CLAUDE_CONFIG_DIR=C:\Users\user\.claude-instances\work
"C:\Users\user\.local\bin\claude.exe" %*
```

`spawn` on Windows calls the `.cmd` launcher and waits for it to exit. PowerShell does not use
`exec`, so the PS session stays active after Claude exits. The `--project` directory change
persists in the session (useful for continuing work in the same directory).

**Execution policy:** Windows may block `.ps1` scripts. Fix:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**PATH:** After `setup.ps1`, the user PATH is updated via the registry. Open a new terminal to
pick it up — existing terminals won't see the change.

## SSH / Non-Interactive Sessions

`~/.local/bin` is typically NOT in PATH for non-interactive SSH sessions.

Workarounds:
```bash
# Open a login shell
ssh -t user@host bash --login

# Or source rc explicitly
ssh user@host "source ~/.bashrc && claudectl list"

# Or use absolute path
ssh user@host "~/.local/bin/claudectl list"
```

## `jq` vs `python3` Fallback

`claudectl config` prefers `jq` for JSON operations. Falls back to `python3` stdlib if `jq` is absent.
Both produce identical results for single top-level key reads/writes. Deep/nested keys require `jq`.

`python3` is required for permission checks in the test suite (replaces `stat`, which differs between
GNU Linux and BSD macOS).
