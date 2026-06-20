#!/usr/bin/env bash
# Physical integration tests for claudectl (bash).
# Deliberately does NOT use `set -e` at runner level — each test captures exit codes explicitly.
# `set -e` would kill the suite on the first `run <cmd>` that intentionally returns non-zero.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/claudectl"

# ── Isolation ─────────────────────────────────────────────────────────────────
# All tests run in a temp dir. Neither ~/.claude-instances nor ~/.local/bin are touched.
TMPROOT=$(mktemp -d)
export CLAUDECTL_BASE="$TMPROOT/instances"
export CLAUDECTL_BIN="$TMPROOT/bin"
mkdir -p "$CLAUDECTL_BIN" "$CLAUDECTL_BASE"
cp "$REPO_ROOT/tests/helpers/fake-claude" "$CLAUDECTL_BIN/claude"
chmod +x "$CLAUDECTL_BIN/claude"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0; fail=0
ok()  { printf "  \033[32mPASS\033[0m %s\n" "$1"; pass=$((pass+1)); }
err() { printf "  \033[31mFAIL\033[0m %s: %s\n" "$1" "$2"; fail=$((fail+1)); }
run() { bash "$SCRIPT" "$@"; }
# Cross-platform permissions: avoids GNU stat -c%a vs BSD stat -f%Lp incompatibility
get_perms() { python3 -c "import os,stat; print(oct(stat.S_IMODE(os.stat('$1').st_mode))[2:])"; }

# ── add ───────────────────────────────────────────────────────────────────────
printf "\n=== add ===\n"
run add myinstance
[ -d "$CLAUDECTL_BASE/myinstance" ]            && ok "add: config dir created"      || err "add:config dir" "missing"
[ "$(get_perms "$CLAUDECTL_BASE/myinstance")" = "700" ] \
                                               && ok "add: config dir chmod 700"    || err "add:chmod" "wrong perms"
[ -f "$CLAUDECTL_BIN/claude-myinstance" ]      && ok "add: launcher created"        || err "add:launcher" "missing"
grep -q "CLAUDE_CONFIG_DIR" "$CLAUDECTL_BIN/claude-myinstance" \
                                               && ok "add: launcher sets CLAUDE_CONFIG_DIR" || err "add:env var" ""
# CRITICAL: launcher must reference $CLAUDECTL_BIN/claude (fake binary), NOT hardcoded ~/.local/bin
grep -q "$CLAUDECTL_BIN/claude" "$CLAUDECTL_BIN/claude-myinstance" \
                                               && ok "add: launcher uses CLAUDECTL_BIN (not hardcoded)" \
                                               || err "add:launcher path" "hardcoded path detected — CRITICAL"

# add: duplicate without --force must exit 1
run add myinstance 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "add: duplicate exits 1 (no --force)" || err "add:duplicate" "got exit $code"

# add: invalid name (space) must exit 1
run add "bad name" 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "add: invalid name (space) exits 1"   || err "add:invalid name" "got exit $code"

# add: invalid name (leading hyphen) must exit 1
run add "-bad" 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "add: invalid name (leading hyphen) exits 1" || err "add:leading-hyphen" "got exit $code"

# add --force: reinitialise an existing instance (exit 0, launcher present)
run add forcetest >/dev/null 2>&1
run add forcetest --force >/dev/null 2>&1; code=$?
[ $code -eq 0 ]  && ok "add --force: reinitialises existing instance (exit 0)" || err "add-force:exit" "got exit $code"
[ -f "$CLAUDECTL_BIN/claude-forcetest" ] && ok "add --force: launcher present after reinit" || err "add-force:launcher" "missing"

# ── list ──────────────────────────────────────────────────────────────────────
printf "\n=== list ===\n"
list_out=$(run list)
echo "$list_out" | grep -q "myinstance" && ok "list: shows new instance"   || err "list" "instance not in output"
echo "$list_out" | grep -q "vanilla"    && ok "list: always shows vanilla" || err "list:vanilla" "missing"

# list --json: schema validation
run list --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert isinstance(data, list), f'not a list, got {type(data)}'
vanilla = next((i for i in data if i['name'] == 'vanilla'), None)
assert vanilla, 'vanilla not in output'
assert 'config_dir' in vanilla, 'vanilla missing config_dir'
assert isinstance(vanilla['logged_in'], bool), f'vanilla logged_in must be bool, got {type(vanilla[\"logged_in\"])}'
inst = next((i for i in data if i['name'] == 'myinstance'), None)
assert inst, 'myinstance not in output'
assert 'config_dir' in inst, 'missing config_dir'
assert isinstance(inst['logged_in'], bool), f'logged_in must be bool, got {type(inst[\"logged_in\"])}'
print('ok')
" && ok "list --json: schema correct (name, config_dir, logged_in:bool)" || err "list --json" "schema mismatch"

# ── path ──────────────────────────────────────────────────────────────────────
printf "\n=== path ===\n"
actual=$(run path myinstance)
[ "$actual" = "$CLAUDECTL_BASE/myinstance" ] && ok "path: returns correct dir"   || err "path" "got '$actual'"
run path vanilla | grep -q ".claude"          && ok "path vanilla: returns .claude dir" || err "path vanilla" ""
run path nonexistent 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "path: exits 1 for unknown instance"  || err "path:missing" "got exit $code"

# ── config ────────────────────────────────────────────────────────────────────
printf "\n=== config ===\n"
run config myinstance; code=$?
[ $code -eq 0 ]  && ok "config: empty instance exits 0"      || err "config:empty exit" "got $code"
result=$(run config myinstance)
printf '%s' "$result" | python3 -c "import json,sys; json.load(sys.stdin)" \
              && ok "config: empty instance returns valid JSON" || err "config:empty JSON" "not valid JSON: $result"

run config myinstance model "claude-opus-4-5"; code=$?
[ $code -eq 0 ]  && ok "config write: exits 0"               || err "config:write exit" "got $code"
[ -f "$CLAUDECTL_BASE/myinstance/settings.json" ] \
              && ok "config write: creates settings.json"     || err "config:write" "file not created"
val=$(run config myinstance model)
[ "$val" = "claude-opus-4-5" ] \
              && ok "config read-back: correct value"         || err "config:readback" "got '$val'"

# config: reading a key that is absent returns empty (no error)
val=$(run config myinstance no_such_key); code=$?
{ [ $code -eq 0 ] && [ -z "$val" ]; } \
              && ok "config: absent key returns empty"        || err "config:absent-key" "exit $code, got '$val'"

# ── clone ─────────────────────────────────────────────────────────────────────
printf "\n=== clone ===\n"
run clone myinstance nonexistent 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "clone: exits 1 if dst doesn't exist" || err "clone:missing-dst" "got exit $code"

run add clonetest
printf '{"oauthToken":"SECRET"}' > "$CLAUDECTL_BASE/myinstance/.credentials.json"
run clone myinstance clonetest
[ -f "$CLAUDECTL_BASE/clonetest/settings.json" ] \
              && ok "clone: settings.json copied"             || err "clone:settings" "not copied"
[ ! -f "$CLAUDECTL_BASE/clonetest/.credentials.json" ] \
              && ok "clone: .credentials.json NOT copied (security check)" \
              || err "clone:credentials" "SECURITY VIOLATION: credentials were copied!"

# clone --deep: copies non-denylisted files/dirs, excludes credentials + cache
run add deepsrc; run add deepdst
printf '{"theme":"dark"}'        > "$CLAUDECTL_BASE/deepsrc/settings.json"
mkdir -p "$CLAUDECTL_BASE/deepsrc/plugins"; printf 'x' > "$CLAUDECTL_BASE/deepsrc/plugins/p.txt"
mkdir -p "$CLAUDECTL_BASE/deepsrc/cache";   printf 'x' > "$CLAUDECTL_BASE/deepsrc/cache/c.bin"
printf '{"oauthToken":"SECRET"}' > "$CLAUDECTL_BASE/deepsrc/.credentials.json"
run clone deepsrc deepdst --deep
[ -f "$CLAUDECTL_BASE/deepdst/settings.json" ]       && ok "clone --deep: settings.json copied"      || err "clone-deep:settings" "not copied"
[ -f "$CLAUDECTL_BASE/deepdst/plugins/p.txt" ]       && ok "clone --deep: non-denylisted dir copied" || err "clone-deep:plugins" "plugins/ not copied"
[ ! -e "$CLAUDECTL_BASE/deepdst/cache" ]             && ok "clone --deep: cache/ excluded (denylist)" || err "clone-deep:cache" "cache/ copied"
[ ! -f "$CLAUDECTL_BASE/deepdst/.credentials.json" ] && ok "clone --deep: .credentials.json excluded (security)" \
              || err "clone-deep:credentials" "SECURITY VIOLATION: credentials were deep-copied!"

# clone (shallow) when src has no settings.json: prints a 'nothing to clone' note, exits 0
run add nosettings; run add nosettings-dst
out=$(run clone nosettings nosettings-dst 2>&1); code=$?
{ [ $code -eq 0 ] && echo "$out" | grep -qi "nothing to clone"; } \
              && ok "clone: no settings.json -> 'nothing to clone' note (exit 0)" || err "clone:no-settings" "got exit $code: $out"

# ── spawn ─────────────────────────────────────────────────────────────────────
printf "\n=== spawn ===\n"
output=$(run spawn myinstance --dry-run 2>&1)
echo "$output" | grep -q "claude-myinstance" \
              && ok "spawn --dry-run: prints launcher path"   || err "spawn --dry-run:path" "launcher not in output"
echo "$output" | grep -q "\[fake-claude\]"   \
              && err "spawn --dry-run" "actually exec'd the fake binary!" \
              || ok "spawn --dry-run: did not execute"

run spawn no-such-instance --dry-run 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "spawn: exits 1 for missing instance" || err "spawn:missing" "got exit $code"

run spawn myinstance --project /no/such/dir --dry-run 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "spawn --project: exits 1 for missing dir" || err "spawn:missing-dir" "got exit $code"

# spawn: args after -- are passed through to claude (visible in --dry-run output)
output=$(run spawn myinstance --dry-run -- --bare -p "hello" 2>&1)
echo "$output" | grep -q -- "--bare" \
              && ok "spawn --dry-run: passes through claude args after --" || err "spawn:passthrough" "args not in output: $output"

# ── status ────────────────────────────────────────────────────────────────────
printf "\n=== status ===\n"
run status; code=$?
[ $code -eq 0 ]  && ok "status: exits 0 (no running instances)" || err "status:exit" "got $code"

run status --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d,list)" \
              && ok "status --json: valid JSON array"         || err "status --json" "invalid JSON"

# ── token ─────────────────────────────────────────────────────────────────────
printf "\n=== token ===\n"
rm -f "$CLAUDECTL_BASE/myinstance/.credentials.json"
run token myinstance 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "token: exits 1 when not logged in"   || err "token:loggedout" "got exit $code"

printf '{"oauthToken":"test-token"}' > "$CLAUDECTL_BASE/myinstance/.credentials.json"
output=$(run token myinstance 2>&1); code=$?
[ $code -eq 0 ]  && ok "token: exits 0 when logged in"       || err "token:exit" "got $code"
echo "$output" | grep -q "CLAUDE_CODE_OAUTH_TOKEN" \
              && ok "token: prints CI usage hint"             || err "token:hint" "CI hint missing"
rm -f "$CLAUDECTL_BASE/myinstance/.credentials.json"

# ── version ───────────────────────────────────────────────────────────────────
printf "\n=== version ===\n"
output=$(run version 2>&1); code=$?
[ $code -eq 0 ]         && ok "version: exits 0"                    || err "version:exit" "got $code"
echo "$output" | grep -q "claudectl" \
                        && ok "version: output contains 'claudectl'" || err "version:output" "missing"
echo "$output" | grep -qE "0\.[0-9]+\.[0-9]+" \
                        && ok "version: output contains semver"      || err "version:semver" "no version number"

# ── setup ─────────────────────────────────────────────────────────────────────
# Hermetic: HOME + XDG_CONFIG_HOME are redirected so real shell rc files are
# never touched. Exercises PATH wiring across bash/zsh/sh/fish, idempotency, and
# the non-fatal behaviour when Claude Code is absent.
printf "\n=== setup ===\n"
FAKEHOME="$TMPROOT/fakehome"
mkdir -p "$FAKEHOME/.config/fish"
: > "$FAKEHOME/.bashrc"; : > "$FAKEHOME/.zshrc"; : > "$FAKEHOME/.profile"; : > "$FAKEHOME/.config/fish/config.fish"

HOME="$FAKEHOME" XDG_CONFIG_HOME="$FAKEHOME/.config" bash "$SCRIPT" setup >/dev/null 2>&1; code=$?
[ $code -eq 0 ] && ok "setup: exits 0" || err "setup:exit" "got $code"
grep -qF "$CLAUDECTL_BIN" "$FAKEHOME/.bashrc"  && ok "setup: wires bash PATH (.bashrc)"  || err "setup:bashrc"  "BIN not in .bashrc"
grep -qF "$CLAUDECTL_BIN" "$FAKEHOME/.zshrc"   && ok "setup: wires zsh PATH (.zshrc)"    || err "setup:zshrc"   "BIN not in .zshrc"
grep -qF "$CLAUDECTL_BIN" "$FAKEHOME/.profile" && ok "setup: wires sh PATH (.profile)"   || err "setup:profile" "BIN not in .profile"
fish_cfg="$FAKEHOME/.config/fish/config.fish"
grep -qE "^set -gx PATH" "$fish_cfg" && grep -qF "$CLAUDECTL_BIN" "$fish_cfg" \
              && ok "setup: wires fish PATH (fish syntax)" || err "setup:fish" "fish PATH line missing or wrong syntax"

# Idempotency: a second run must not duplicate the PATH entry
HOME="$FAKEHOME" XDG_CONFIG_HOME="$FAKEHOME/.config" bash "$SCRIPT" setup >/dev/null 2>&1
count=$(grep -cF "$CLAUDECTL_BIN" "$FAKEHOME/.bashrc")
[ "$count" -eq 1 ] && ok "setup: idempotent (.bashrc not duplicated)" || err "setup:idempotent" "got $count entries"

# Non-fatal when Claude Code is absent (CLAUDECTL_BIN points at a dir with no claude binary)
NOCLAUDE="$TMPROOT/noclaude"; mkdir -p "$NOCLAUDE"
HOME="$FAKEHOME" XDG_CONFIG_HOME="$FAKEHOME/.config" CLAUDECTL_BIN="$NOCLAUDE" bash "$SCRIPT" setup >/dev/null 2>&1; code=$?
[ $code -eq 0 ] && ok "setup: non-fatal when Claude Code absent" || err "setup:noclaude" "got exit $code"

# ── reset ─────────────────────────────────────────────────────────────────────
printf "\n=== reset ===\n"
printf '{"theme":"dark"}' > "$CLAUDECTL_BASE/myinstance/settings.json"
run reset myinstance --force
[ -d "$CLAUDECTL_BASE/myinstance" ]                  && ok "reset: config dir preserved"   || err "reset:dir" "dir gone"
[ ! -f "$CLAUDECTL_BASE/myinstance/settings.json" ] && ok "reset: settings.json wiped"    || err "reset:settings" "file still exists"
[ -f "$CLAUDECTL_BIN/claude-myinstance" ]            && ok "reset: launcher kept"          || err "reset:launcher" "launcher removed"
run reset vanilla 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "reset vanilla: exits 1 (blocked)"   || err "reset:vanilla" "got exit $code"

# ── remove ────────────────────────────────────────────────────────────────────
printf "\n=== remove ===\n"
run remove myinstance --force
[ ! -f "$CLAUDECTL_BIN/claude-myinstance" ] && ok "remove: launcher removed"   || err "remove:launcher" "still exists"
[ -d "$CLAUDECTL_BASE/myinstance" ]         && ok "remove: config dir kept"    || err "remove:config" "dir removed unexpectedly"

run add fullremove
run remove fullremove --purge --force
[ ! -f "$CLAUDECTL_BIN/claude-fullremove" ] && ok "remove --purge: launcher removed"   || err "remove-purge:launcher" ""
[ ! -d "$CLAUDECTL_BASE/fullremove" ]       && ok "remove --purge: config dir removed" || err "remove-purge:config" "dir still exists"

run remove vanilla 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "remove vanilla: exits 1 (blocked)" || err "remove:vanilla" "got exit $code"

# ── error handling ────────────────────────────────────────────────────────────
printf "\n=== error handling ===\n"
run no-such-command 2>/dev/null; code=$?
[ $code -eq 2 ]  && ok "unknown command: exits 2" || err "unknown command" "got exit $code"

# ── help ──────────────────────────────────────────────────────────────────────
printf "\n=== help ===\n"
for cmd in add list path reset remove spawn status clone config token version setup; do
    run help "$cmd" >/dev/null 2>&1 && ok "help $cmd: exits 0" || err "help $cmd" "non-zero exit"
done
run help no-such-subcommand 2>/dev/null; code=$?
[ $code -eq 1 ]  && ok "help: unknown subcommand exits 1" || err "help:unknown" "got exit $code"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n"
printf "Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$pass" "$fail"
[ $fail -eq 0 ] && exit 0 || exit 1
