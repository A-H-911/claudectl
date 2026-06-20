# Command Reference

## `claudectl add <name> [--force]`

Create a new isolated Claude Code instance.

**Creates:**
- `$CLAUDECTL_BASE/<name>/` — config directory (chmod 700)
- `$CLAUDECTL_BIN/claude-<name>` — launcher script (Linux/Mac) or `claude-<name>.cmd` (Windows)

**Flags:**
- `--force` — overwrite if the instance already exists

**Name rules:** letters, numbers, hyphens, underscores only. No spaces. Must start with a letter or digit.

**Exit codes:** 0 success, 1 invalid name / already exists (no --force)

```bash
claudectl add work
claudectl add personal
claudectl add ci --force
```

After adding, run `claude-<name>` and complete `/login`. Each instance keeps its own credentials.

---

## `claudectl list [--json]`

List all managed instances plus the built-in `vanilla` instance.

**Flags:**
- `--json` — output as JSON array

**JSON schema:**
```json
[
  {"name": "vanilla", "config_dir": "/home/user/.claude", "logged_in": true},
  {"name": "work", "config_dir": "/home/user/.claude-instances/work", "logged_in": false}
]
```

`logged_in` is a **boolean** (not a string).

```bash
claudectl list
claudectl list --json | jq '.[].name'
```

---

## `claudectl path <name>`

Print the config directory for an instance.

**Exit codes:** 0 success, 1 unknown instance

```bash
claudectl path work
cd "$(claudectl path work)"
```

---

## `claudectl reset <name> [--force]`

Wipe all config files in an instance. The launcher script is preserved.

**Flags:**
- `--force` — skip confirmation prompt

**Guards:** The `vanilla` instance cannot be reset (exits 1)

```bash
claudectl reset work --force
```

---

## `claudectl remove <name> [--purge] [--force]`

Remove the launcher script for an instance.

**Flags:**
- `--purge` — also remove the config directory (irreversible)
- `--force` — skip confirmation prompt

**Guards:** The `vanilla` instance cannot be removed (exits 1)

```bash
claudectl remove old-project
claudectl remove old-project --purge --force
```

---

## `claudectl spawn <name> [--project <dir>] [--dry-run] [-- <claude-args>...]`

Launch Claude Code using a specific instance.

**Flags:**
- `--project <dir>` — change directory before spawning (exits 1 if dir missing)
- `--dry-run` — print the exact command that would run; do NOT execute
- `--` — everything after `--` is passed directly to claude

`--bare` skips hooks, LSP init, and plugin sync. Use for scripted calls.

```bash
claudectl spawn work
claudectl spawn work --project ~/repos/myapp
claudectl spawn work --dry-run -- --bare -p "explain this"
```

---

## `claudectl status [--json]`

Show currently running Claude Code instances.

**Linux/macOS:** Reads `/proc/*/environ` for `CLAUDE_CONFIG_DIR` per process.
**Windows:** `Get-Process "claude*"` — PID + start time only.

```bash
claudectl status
claudectl status --json
```

---

## `claudectl clone <src> <dst> [--deep]`

Copy configuration from one instance to another.

**Default:** copies `settings.json` only.
**`--deep`:** copies everything except the denylist (`.credentials.json`, `cache/`, `backups/`, `sessions/`, `history.jsonl`, `telemetry/`, `usage-data/`, `mcp-needs-auth-cache.json`).

```bash
claudectl clone work staging
claudectl clone work staging --deep
```

---

## `claudectl config <name> [<key> [<value>]]`

Read or write `settings.json` for an instance.

| Usage | Effect |
|-------|--------|
| `claudectl config <name>` | print full `settings.json` (prints `{}` if no file) |
| `claudectl config <name> <key>` | read one key |
| `claudectl config <name> <key> <val>` | set one key |

**Requires:** `jq` (preferred) or `python3` (fallback).

```bash
claudectl config work model claude-opus-4-5
```

---

## `claudectl token <name>`

Show the credentials file path and CI usage hint.

**Exits 1** if the instance has not completed `/login`.

```bash
claudectl token work
export CLAUDE_CODE_OAUTH_TOKEN=$(jq -r .oauthToken "$(claudectl path work)/.credentials.json")
```

---

## `claudectl version`

Print claudectl version and Claude Code version.

---

## `claudectl setup [--update]`

Configure PATH and verify installation.

**Linux / macOS** — appends `$CLAUDECTL_BIN` to whichever shell rc files **already exist**:

| Shell | File | Line written |
|-------|------|--------------|
| bash | `~/.bashrc` | `export PATH="$BIN:$PATH"` |
| zsh | `~/.zshrc` | `export PATH="$BIN:$PATH"` |
| sh | `~/.profile` | `export PATH="$BIN:$PATH"` |
| fish | `${XDG_CONFIG_HOME:-~/.config}/fish/config.fish` | `set -gx PATH "$BIN" $PATH` |

Existing entries are never duplicated; rc files that don't exist are left untouched (if none
exist, setup prints a manual-PATH instruction). `setup.sh` delegates to this command, so the
installer and the `setup` subcommand share one PATH-wiring implementation.

**Windows** — adds `$CLAUDECTL_BIN` to the user PATH via the registry. Open a new terminal to pick it up.

After wiring PATH, setup reports whether the Claude Code binary is present. A missing binary is a
**note, not an error** — `setup` still exits 0 (changed in 0.2.0; previously exited 1).

**Flags:**
- `--update` — self-update claudectl from `$CLAUDECTL_UPDATE_URL`. Requires `curl`.

```bash
claudectl setup
claudectl setup --update
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Operational error: instance not found, not logged in, validation failed |
| `2` | Usage error: unknown subcommand, missing required argument |

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDECTL_BASE` | `~/.claude-instances` | Instance storage root |
| `CLAUDECTL_BIN` | `~/.local/bin` | Binary/launcher installation dir |
| `CLAUDECTL_UPDATE_URL` | GitHub raw URL | Self-update source |
