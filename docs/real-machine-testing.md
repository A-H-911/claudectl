# Real-Machine Testing

GitHub CI runs the suites on pristine hosted runners. That leaves a whole class of
behavior **unverified**, because the runners can't reproduce it:

- **Linux** — `/proc/*/environ` per-instance PID attribution in `status`; real `exec` spawn.
- **macOS** — stock **bash 3.2**, BSD `stat`/utilities, and the `/proc`-absent `status` path.
- **Windows** — **Windows PowerShell 5.1**, which is what the production `claudectl.cmd` shim
  actually runs (`powershell`, not `pwsh`). 5.1 reads a BOM-less `.ps1` as Windows-1252, so a
  single non-ASCII byte in a string breaks parsing — invisible to a pwsh-7-only CI.

So **every change is also validated on three real machines** (Linux, macOS, Windows) using
`tests/real-machine-test.ps1`. This is part of the test plan, not an optional extra.

## What it runs (the matrix)

| Host | Runs |
|------|------|
| Linux | `test_claudectl.sh` (full unit suite) + `smoke.sh` (incl. live `/proc` attribution) |
| macOS | `test_claudectl.sh` + `smoke.sh` (incl. `/proc`-absent clean-status) |
| Windows | `test_claudectl.ps1` under **PowerShell 5.1** *and* **pwsh 7** + `smoke.ps1` under 5.1 |

Both PowerShell versions are exercised on Windows because production uses 5.1 while
CI historically used 7. Each unit suite is driven by the **same** interpreter that
launches it (see `$PSExe` in `test_claudectl.ps1`), so `powershell -File ...` tests 5.1
and `pwsh -File ...` tests 7.

## Safety model

- **The suites and smoke harness are hermetic / sandboxed** — they point
  `CLAUDECTL_BASE`/`CLAUDECTL_BIN` (and `HOME` for the `setup` test) at temp dirs and never
  touch the host's real `~/.claude-instances`, launchers, rc files, or registry. So routine
  runs need **no VM snapshot** — nothing on the target is modified.
- Snapshots are only warranted for genuinely destructive one-offs (e.g. removing a predecessor
  tool), not for this test loop.
- **Credentials never touch a log, argv, or disk.** SSH passwords are read from 1Password
  (read-only) straight into in-memory `SecureString`s; `op://` *references* are config, the
  resolved values are not printed.

## Prerequisites

On the machine you run the orchestrator **from**:
- PowerShell (5.1 or 7), the **Posh-SSH** module (`Install-Module Posh-SSH -Scope CurrentUser`),
  and the **1Password CLI** (`op`) with desktop-app CLI integration enabled + unlocked.

On each **target** host: `git` and an SSH server (port 22). On the **Windows** target, install
**both** `powershell` (5.1, built in) and **`pwsh` 7** so both versions are covered; if pwsh 7 is
absent, that row reports `SKIPPED` (CI still covers pwsh 7).

1Password: one item per host, tagged however you like, with a `url` field holding `user@host`
and a `password` field. Reference them by item name in the config below.

## Configure

Copy the template and fill in your hosts (the real file is gitignored):

```bash
cp tests/real-machine-hosts.example.json tests/real-machine-hosts.json
```

```jsonc
{
  "repo_url": "https://github.com/A-H-911/claudectl.git",
  "ref": "main",                 // default git ref to clone on each host
  "vault": "Personal",           // 1Password vault holding the items
  "hosts": [
    { "name": "linux",   "type": "linux",   "op_item": "ssh-my-linux-host" },
    { "name": "macos",   "type": "macos",   "op_item": "ssh-my-mac" },
    { "name": "windows", "type": "windows", "op_item": "ssh-my-windows-host" }
  ]
}
```

## Run

```powershell
# 1. push the branch you want to validate (each host git-clones the ref)
git push -u origin my-branch

# 2. run the full matrix on all hosts
pwsh -File tests/real-machine-test.ps1 -Ref my-branch
#   or under Windows PowerShell:  powershell -File tests/real-machine-test.ps1 -Ref my-branch

# subset to one host while iterating
pwsh -File tests/real-machine-test.ps1 -Ref my-branch -Only windows
```

The orchestrator clones the ref on each host into a temp dir, runs the matrix, cleans up, and
prints a summary. It exits **non-zero if any row is not `N passed, 0 failed`** (rows marked
`SKIPPED`, e.g. pwsh 7 absent, do not fail the run), so it slots into a pre-merge gate.

> Because each host clones a **git ref**, push your branch first — the orchestrator tests
> committed code, mirroring what will merge. It is not a substitute for the hermetic CI suites;
> it is the real-hardware layer on top of them.
