# User Guide

## Workflow 1: Separate Work and Personal Instances

```bash
claudectl add work
claudectl add personal

claude-work      # /login with work account
claude-personal  # /login with personal account

claudectl list
# NAME      CONFIG_DIR                              LOGGED_IN
# vanilla   /home/user/.claude                      yes
# work      /home/user/.claude-instances/work       yes
# personal  /home/user/.claude-instances/personal   yes
```

Each instance has its own credentials, session history, and settings.

---

## Workflow 2: CI — Headless Task with OAuth Token

```bash
# Local: set up and authenticate
claudectl add ci
claude-ci    # /login

# Get token for CI
claudectl token ci
# CI usage: export CLAUDE_CODE_OAUTH_TOKEN=$(jq -r .oauthToken ...)

# In CI pipeline
export CLAUDE_CODE_OAUTH_TOKEN=$(jq -r .oauthToken "$(claudectl path ci)/.credentials.json")
claudectl spawn ci -- --bare -p "summarize the diff in this PR"
```

`--bare` skips hooks, LSP init, and plugin sync — recommended for scripted calls.

---

## Workflow 3: Team Setup — Share Settings, Customize Per-Instance

```bash
claudectl add team-base
claudectl config team-base model claude-opus-4-5
claudectl config team-base theme dark

claudectl add alice
claudectl clone team-base alice        # copies settings.json only

claudectl add bob
claudectl clone team-base bob --deep   # copies settings + plugins (not credentials)

claude-alice   # /login with alice's account
claude-bob     # /login with bob's account
```

Credentials are NEVER copied by `clone` — each person authenticates separately.

---

## Workflow 4: Project-Based Instances

```bash
claudectl add myapp
claudectl add legacy-api

claudectl spawn myapp --project ~/repos/myapp
claudectl spawn legacy-api --project ~/repos/old-api

# Or make shell aliases
alias work-myapp="claudectl spawn myapp --project ~/repos/myapp"
alias work-legacy="claudectl spawn legacy-api --project ~/repos/old-api"
```

---

## Workflow 5: Cleanup

```bash
# Check what's running
claudectl status

# Wipe config, keep launcher (re-login after)
claudectl reset work --force

# Remove launcher only (config kept)
claudectl remove old-project

# Full teardown (irreversible)
claudectl remove old-project --purge --force
```

---

## Quick Reference

```bash
# Add and authenticate
claudectl add <name>
claude-<name>                  # then /login

# Daily usage
claude-<name>
claudectl spawn <name> --project <dir>

# Inspect
claudectl list --json
claudectl path <name>
claudectl status

# Settings
claudectl config <name>
claudectl config <name> model claude-opus-4-5
claudectl clone <src> <dst>

# CI
claudectl token <name>
claudectl spawn <name> -- --bare -p "<prompt>"
```
