# Real-Machine Test Hardening for claudectl

> **Status:** COMPLETED — landed in PRs #6, #8, #9 (v0.2.1 → v0.2.3). This is the original
> plan **as drafted**; execution refined it (see **Outcome** below). Operator-specific details
> (host addresses, etc.) have been redacted.

## Outcome (what actually shipped)

- **Headline:** real-machine testing immediately found a **critical Windows bug** — the production
  entry point `claudectl.cmd` runs `claudectl.ps1` under Windows PowerShell **5.1**, which read the
  BOM-less script as Windows-1252 and failed to parse the non-ASCII em-dashes in its strings.
  `claudectl` was **non-functional on stock Windows**; CI never caught it because it only ran pwsh 7.
  Fixed by making `claudectl.ps1` pure ASCII, with a CI step that now guards the real 5.1 path.
- **Validated on three real machines** (Linux, macOS, Windows): the full unit suites + a new
  `tests/smoke.{sh,ps1}` harness, exercising the Linux `/proc` attribution path and **both** PowerShell
  versions (5.1 + pwsh 7).
- **Made repeatable:** `tests/real-machine-test.ps1` orchestrates the full matrix over SSH on every
  change — see [../real-machine-testing.md](../real-machine-testing.md).
- **Refinements vs this draft:** Windows moved from a host to a **Hyper-V VM**; the predecessor tool
  (claudectl v0.1.0) was reverted via a **Hyper-V snapshot** rather than a tar backup (its config dir
  could hold a real `.credentials.json`, so an off-VM backup was rejected); SSH used
  **1Password-sourced passwords held in memory** (Posh-SSH `SecureString`) rather than only key auth.

## Context

`claudectl` is validated today only by GitHub Actions on clean hosted runners (Linux + macOS bash
suite, Windows pwsh suite). Those runners are pristine: no real shell rc files, no live `claude`
process, no real `~/.claude-instances`, pwsh 7 always present. As a result a whole class of behavior
is **never exercised**: real `/proc` PID attribution in `status`, real `exec` spawn, macOS bash 3.2 /
BSD utils, the `/proc`-absent macOS `status` path, Windows `icacls` ACLs + registry PATH, real
shell-rc wiring, and **Windows PowerShell 5.1** (CI only ever runs pwsh 7).

The goal: run the suites **and** real end-to-end flows on three physical machines (Windows = this PC,
macOS = MBP over SSH, Ubuntu = VM over SSH), turn the findings into durable fixes + a reusable
real-machine smoke harness, and land them via PR. The Ubuntu VM additionally carries an **earlier
predecessor tool** that must be read, backed up, and fully uninstalled before it can serve as a clean
test host.

## Decisions (from user)

- **Windows runtime:** run under Windows PowerShell **5.1 first** (default-user signal), then install
  **pwsh 7 via winget** and re-run for CI parity.
- **Scope:** suites + manual real-flow checks **+ harden & commit fixes** (largest scope).
- **VM predecessor:** **back up** (script, launchers, PATH edits, config dirs — may hold real
  `.credentials.json`) to a timestamped tar, **then** uninstall totally.

## Safety model (applies to every phase)

- **Hermetic suites are already safe** — `tests/test_claudectl.sh` / `.ps1` redirect
  `CLAUDECTL_BASE`/`CLAUDECTL_BIN` (and `HOME`+`XDG_CONFIG_HOME` for the `setup` case), so they never
  touch real config. Run them as-is anywhere.
- **Manual flows use throwaway sandboxes**: `export CLAUDECTL_BASE=$(mktemp -d) CLAUDECTL_BIN=$(mktemp -d)`,
  disposable instance names (`rmtest`, `smoke`), full cleanup after. Never mutate the user's real
  `~/.claude-instances`, `~/.local/bin`, rc files, or Windows registry PATH.
- **Never read, copy, echo, or transmit any `.credentials.json`** contents. `claudectl token` only
  prints the *path* + a hint — that is the only credential-adjacent command we run.
- **SSH = key/agent auth only.** No passwords on the command line (global security rule + instinct).
  Connectivity is established by the user interactively; thereafter non-interactive `ssh host 'cmd'`.
- **`setup` PATH tests run against a redirected `HOME`** (as the hermetic test does) so real rc files /
  registry are never modified. If a real registry/rc check is unavoidable on Windows, snapshot the User
  PATH first and restore it.
- **Do not test `setup --update`** against real GitHub (it self-replaces the installed script).

## Execution plan

### Phase 0 — Local prep (SSH is a hard gate)
1. Confirm clean tree on `main`; branch `test/real-machine-hardening`.
2. Draft the new smoke harness (below) locally and dry-run it under Git Bash with a sandbox
   `CLAUDECTL_BASE`/`CLAUDECTL_BIN`.
3. **SSH connectivity gate** (Phases 2–3 depend entirely on non-interactive `ssh host 'cmd'`; the
   `100.x` addresses look like Tailscale, so key auth likely already works). Verify `ssh <host> true`
   returns 0 **with no prompt**. If it prompts for a password I cannot proceed (no password flags, by
   rule) — **fallback decided upfront**: the user opens one authenticated SSH **ControlMaster** master
   connection interactively (`ssh -M -S <socket> host`), and I reuse it via `ssh -S <socket> host 'cmd'`.
4. **Remote prerequisite probe** before any test: `ssh host 'uname -a; bash --version; python3 -V;
   git --version; command -v claude jq'` per host. The bash suite hard-depends on `python3`
   (`get_perms` + JSON schema test) — a missing `python3` would otherwise read as a claudectl failure.

### Phase 1 — Windows (this PC)
> Note: the suite runner hardcodes `pwsh` (`tests/test_claudectl.ps1:23` → `pwsh -NoProfile -File`),
> so the **suite always runs under pwsh 7**, never 5.1. To honor the 5.1 decision I exercise the
> **script directly** under 5.1, not via the suite.
1. **5.1 pass (script-direct):** drive `powershell.exe -File scripts\claudectl.ps1 <cmd>` for the full
   manual real-flow (step 3) under Windows PowerShell 5.1, watching specifically for 5.1 quirks:
   `ConvertTo-Json` output, `Set-Content -Encoding utf8` (5.1 BOM behavior), and `$args` slicing in the
   dispatch block. This is the only way to learn whether the `.ps1` behaves on a default-Windows 5.1 box.
2. **Install pwsh 7:** `winget install Microsoft.PowerShell`; run `tests/test_claudectl.ps1` under pwsh 7
   (CI parity) — this is the suite's real home.
3. **Manual real-flow (sandboxed):** with throwaway `CLAUDECTL_BASE`/`CLAUDECTL_BIN`, exercise
   `add → list → config → clone → token(path only) → status → spawn --dry-run → remove`. Verify the
   `.cmd` launcher contents and that `icacls` actually restricted the dir (the suite never asserts ACLs —
   `claudectl.ps1:54,129`).
4. Note the bash-suite Git-Bash artifacts already seen locally (`add:chmod`, `list --json` python harness)
   as Windows-only, for the hardening phase.

### Phase 2 — macOS (MBP via SSH)
1. `git clone` the repo (or `rsync` the working branch) into a temp dir on the MBP.
2. Run `tests/test_claudectl.sh` — real BSD `stat`, bash 3.2, default zsh.
3. **macOS-specific checks:** confirm `status` exits 0 cleanly with no `/proc` (`claudectl:217`) and no
   leaked `stat -c%Y` error; confirm the `get_perms` python check passes (real `chmod 700`).
4. **Manual real-flow (sandboxed):** same add→…→remove loop; plus a real `setup` against a **redirected
   HOME** to confirm zsh `.zshrc` wiring on a real Mac.
5. If `claude` is installed on the MBP: one real end-to-end `spawn smoke -- --version` (exec path) using
   a sandbox instance — exits immediately, no login needed.

### Phase 3 — Ubuntu VM (predecessor removal, then test)
1. SSH in; locate and **read the predecessor's `*.md` user guide**; map its footprint to the known
   instance-manager shape: a CLI script in `~/.local/bin` (or elsewhere), `claude-*`/launcher files,
   PATH lines in `~/.bashrc`/`~/.zshrc`/`~/.profile`/fish (grep its marker), and config dir(s)
   (its `~/.claude-instances` equivalent, possibly with real `.credentials.json`).
2. **Back up**: `tar czf ~/predecessor-backup-<ts>.tgz` over every identified path (script, launchers,
   rc files, config dirs). Verify the archive lists before deleting.
3. **Uninstall totally**: remove its script + launchers, strip its PATH block from each rc file
   (grep-out its marker, not a blunt sed), remove its config dirs. Leave the vanilla `~/.claude`
   untouched. Re-login shell and confirm its command is gone from PATH.
4. Install/clone claudectl; run `tests/test_claudectl.sh` (real Linux).
5. **The Linux-only payoff:** `status` scans `/proc/*/environ` for *any* process carrying
   `CLAUDE_CONFIG_DIR` and matches it to an instance dir — it never checks the process name
   (`claudectl:218-232`). So a real/logged-in claude is unnecessary: run
   `CLAUDE_CONFIG_DIR="$CLAUDECTL_BASE/smoke" sleep 60 &`, then assert real `status` / `status --json`
   attributes that PID to the `smoke` instance. Deterministic, no claude install, no login, no
   credentials touched. Kill the sleep + remove the sandbox after.

### Phase 4 — Harden & commit (PR)
Turn findings into durable changes on `test/real-machine-hardening`:
- **New real-machine smoke harness** `tests/smoke.sh` + `tests/smoke.ps1` (see below).
- **Platform fixes** for any real bug surfaced (e.g. macOS `status`/`elapsed` cleanliness; pwsh 5.1
  incompatibilities; ACL assertion gap).
- **Git-Bash guard**: make the bash suite skip/`xfail` the `chmod`-mode and `python3`-harness assertions
  under MSYS/Git-Bash (`uname` detection) so a Windows dev running the bash suite sees green, without
  weakening Linux/macOS coverage.
- Update `CHANGELOG.md` + bump `VERSION` (PATCH) in both scripts.
- Open PR; require Linux + macOS + Windows CI green before squash-merge (linear history).

## New artifact — real-machine smoke harness

`tests/smoke.{sh,ps1}`: a **non-hermetic, real-`claude`-aware** end-to-end script (distinct from the
hermetic unit suites). It runs the full lifecycle against a throwaway `CLAUDECTL_BASE`/`CLAUDECTL_BIN`,
asserts behavior, optionally does a real `spawn -- --version` when `claude` is present, and is safe to
invoke over SSH non-interactively (`ssh host 'bash smoke.sh'`). This becomes the repeatable
"does it actually work on this box" check the project currently lacks.

## Benefits

- Surfaces platform bugs the clean CI runners structurally cannot: real rc/PATH wiring, live `/proc`
  attribution, `exec` spawn, macOS BSD/bash-3.2, Windows 5.1 vs 7, `icacls`/registry.
- Validates the tool's actual reason to exist — SSH/headless usage and per-instance isolation — on
  real hardware.
- Proves the **migration path** (predecessor → claudectl), the real adoption story for the VM.
- Leaves behind a reusable smoke harness + Git-Bash-friendly suite, lowering future regression cost.

## Risks & guardrails

| Risk | Mitigation |
|---|---|
| Wiping/altering real `.credentials.json` (OAuth tokens) | Hermetic suites use overrides; manual flows use temp sandboxes; never touch/print creds; back up VM before any delete |
| VM uninstall removes wrong files / real login state | Read its guide first, enumerate, back up to timestamped tar, grep-out PATH markers (not blunt sed), leave vanilla `~/.claude` |
| Mutating real rc files / Windows registry PATH during `setup` test | Run `setup` against redirected `HOME`; if registry unavoidable, snapshot + restore User PATH |
| SSH password leakage | Key/agent auth only; no password flags — user authenticates interactively |
| Installing pwsh 7 changes this PC | Standard, reversible winget install; user opted in |
| `spawn` real exec launches interactive Claude | Use `--dry-run` for assertions; only real-exec via `-- --version`, which exits immediately |
| Self-update self-modifies installed script | `setup --update` excluded from testing |

## Verification

- **Per machine:** `tests/` suite result (pass count vs the known-good baseline) + the new `smoke`
  harness exit 0, captured to a short report.
- **Linux:** real `status --json` returns the sandbox instance's PID/`config_dir` while a live
  `CLAUDE_CONFIG_DIR` process runs, then empty after cleanup.
- **macOS:** suite green on real BSD/bash-3.2; `status` exits 0 with no error.
- **Windows:** suite green under pwsh 7 + script-direct 5.1 flow clean; `.cmd` launcher + ACL verified.
- **Final:** all three CI checks green on the PR; `CHANGELOG`/`VERSION` updated; sandboxes and the VM
  predecessor backup accounted for.

## Open concerns to resolve before execution

_(Reserved — add your concerns here on the next pass; I'll address each before any machine is touched.)_

---

_The original reload prompt and operator host addresses have been redacted — this plan is complete.
The live runbook for re-running the real-machine matrix is
[../real-machine-testing.md](../real-machine-testing.md)._
