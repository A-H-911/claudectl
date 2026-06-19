# Architecture

## How `CLAUDE_CONFIG_DIR` Isolation Works

Claude Code reads its configuration from a single directory. By default that directory is `~/.claude`.
The `CLAUDE_CONFIG_DIR` environment variable redirects it to any other path.

```
~/.local/bin/claude-work   ←  launcher script
  └── sets: CLAUDE_CONFIG_DIR=~/.claude-instances/work
  └── exec: ~/.local/bin/claude "$@"
                                │
                                ▼
                    ~/.claude-instances/work/
                    ├── settings.json        ← instance-specific settings
                    ├── .credentials.json    ← instance-specific auth
                    ├── history.jsonl        ← instance-specific session history
                    └── plugins/             ← instance-specific plugins
```

All instances share the same Claude Code binary. No binary duplication. No subprocess forking.

## What IS Reliably Isolated

| Item | Isolated | Notes |
|------|----------|-------|
| OAuth credentials / login session | Yes | `.credentials.json` per instance |
| User settings (`settings.json`) | Yes | Theme, model, keybindings |
| Session history (`history.jsonl`) | Yes | Separate per instance |
| MCP server plugins | Mostly | See Known Limitations |
| Installed plugins | Mostly | See Known Limitations |

## Known Limitations

`CLAUDE_CONFIG_DIR` is not a perfect sandbox. As of Claude Code 2.x, some components
still reference `~/.claude` directly:

| Issue | Status | Workaround |
|-------|--------|------------|
| `~/.claude/CLAUDE.md` global instructions may still load | Known (GitHub #31649) | Keep `~/.claude/CLAUDE.md` intentionally minimal |
| LSP plugin installation sometimes writes to `~/.claude` | Known (GitHub #57683) | Manually copy LSP config after install |
| Skills directory sometimes reads from `~/.claude` | Known (GitHub #15071) | Symlink or copy skills into instance dir |
| Plugin marketplace cache | Known | Cache may cross instances |

**This does not make claudectl useless.** Credentials, settings, and session history — the things
that matter for separate accounts/contexts — ARE reliably isolated.

## When to Use claude-squad Instead

[claude-squad](https://github.com/smtg-ai/claude-squad) (7.8k ⭐) takes a different approach:
tmux sessions + git worktrees for complete process-level isolation.

| Use case | claudectl | claude-squad |
|----------|-----------|--------------|
| Separate work / personal accounts | Best fit | Works |
| Long-running parallel tasks in one terminal | Works | Best fit |
| Minimal overhead | Best fit | Heavier |
| Needs complete process isolation | Limited | Best fit |
| Cross-platform (Windows) | Yes | Linux/Mac only |

## Thin Launcher Design

`claudectl add` writes a launcher script rather than copying the binary. This means:

- **One binary, many configs**: Claude Code updates apply to all instances automatically
- **Atomic switch**: `export CLAUDE_CONFIG_DIR=...` before running any command achieves the same effect
- **No daemon**: No background process, no port binding, no IPC

## Directory Layout at Runtime

```
~/.claude-instances/          (CLAUDECTL_BASE)
├── work/
│   ├── settings.json
│   ├── .credentials.json
│   └── history.jsonl
├── personal/
│   └── settings.json
└── ci/
    └── .credentials.json

~/.local/bin/                 (CLAUDECTL_BIN)
├── claude                    ← the real Claude Code binary
├── claudectl                 ← claudectl script
├── claude-work               ← launcher (sets CLAUDE_CONFIG_DIR)
├── claude-personal           ← launcher
└── claude-ci                 ← launcher
```

## Environment Variables

| Variable | Default | Override Use Case |
|----------|---------|-------------------|
| `CLAUDECTL_BASE` | `~/.claude-instances` | Tests, custom storage location |
| `CLAUDECTL_BIN` | `~/.local/bin` | Tests, custom install dir |
| `CLAUDECTL_UPDATE_URL` | GitHub raw URL | Forks point to their own repo |

`CLAUDECTL_BASE` and `CLAUDECTL_BIN` are the primary extension points for testing.
The test suite uses them to create a fully isolated temp directory, never touching the real paths.
