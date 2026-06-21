#!/usr/bin/env bash
# smoke.sh — real-machine end-to-end smoke test for claudectl (bash: Linux/macOS).
#
# Distinct from tests/test_claudectl.sh (the hermetic unit suite): this drives the
# FULL lifecycle on whatever box it runs on, and — when CLAUDECTL_SMOKE_REAL_CLAUDE=1
# and a real `claude` is on PATH — exercises the real `spawn` exec path. It is still
# SAFE: everything runs inside a temp sandbox (CLAUDECTL_BASE/CLAUDECTL_BIN point at
# mktemp dirs), so it never touches your real ~/.claude-instances or ~/.local/bin.
#
# Usage:
#   bash tests/smoke.sh                      # safe: stub claude, no real exec
#   CLAUDECTL_SMOKE_REAL_CLAUDE=1 bash tests/smoke.sh   # also test real `claude --version`
#
# Exit 0 iff every assertion passes. Safe to run over SSH non-interactively.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/claudectl"
[ -f "$SCRIPT" ] || { printf 'smoke: cannot find scripts/claudectl at %s\n' "$SCRIPT" >&2; exit 2; }

# ── Sandbox (never touches real config) ─────────────────────────────────────────
TMPROOT="$(mktemp -d)"
export CLAUDECTL_BASE="$TMPROOT/instances"
export CLAUDECTL_BIN="$TMPROOT/bin"
mkdir -p "$CLAUDECTL_BASE" "$CLAUDECTL_BIN"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
err()  { printf '  \033[31mFAIL\033[0m %s: %s\n' "$1" "$2"; fail=$((fail+1)); }
note() { printf '  \033[33mNOTE\033[0m %s\n' "$1"; }
run()  { bash "$SCRIPT" "$@"; }

is_gitbash() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0;; *) return 1;; esac; }

# Provision the sandbox `claude` the launcher will exec.
REAL_EXEC=0
if [ "${CLAUDECTL_SMOKE_REAL_CLAUDE:-0}" = "1" ] && command -v claude >/dev/null 2>&1; then
    ln -s "$(command -v claude)" "$CLAUDECTL_BIN/claude" 2>/dev/null \
        || cp "$(command -v claude)" "$CLAUDECTL_BIN/claude"
    REAL_EXEC=1
    note "real-claude mode: launcher will exec $(command -v claude)"
else
    # Minimal stub that identifies itself so we can prove --dry-run did NOT exec it.
    printf '#!/usr/bin/env bash\necho "[smoke-stub-claude] $*"\n' > "$CLAUDECTL_BIN/claude"
    chmod +x "$CLAUDECTL_BIN/claude"
fi

printf '\n=== claudectl smoke: %s (%s) ===\n' "$(uname -s)" "$(uname -m)"

# ── add ─────────────────────────────────────────────────────────────────────────
run add smoke >/dev/null 2>&1
[ -d "$CLAUDECTL_BASE/smoke" ]            && ok "add: config dir created"          || err "add:dir" "missing"
[ -f "$CLAUDECTL_BIN/claude-smoke" ]      && ok "add: launcher created"            || err "add:launcher" "missing"
grep -q "CLAUDE_CONFIG_DIR" "$CLAUDECTL_BIN/claude-smoke" \
                                          && ok "add: launcher sets CLAUDE_CONFIG_DIR" || err "add:env" "missing"
grep -q "$CLAUDECTL_BIN/claude" "$CLAUDECTL_BIN/claude-smoke" \
                                          && ok "add: launcher points at sandbox bin" || err "add:binpath" "hardcoded path"
if is_gitbash; then
    note "Git Bash: skipping chmod-700 perms assertion (NTFS emulates mode bits)"
elif command -v python3 >/dev/null 2>&1; then
    perms="$(python3 -c "import os,stat; print(oct(stat.S_IMODE(os.stat('$CLAUDECTL_BASE/smoke').st_mode))[2:])")"
    [ "$perms" = "700" ]                  && ok "add: config dir chmod 700"        || err "add:perms" "got $perms"
else
    note "python3 absent: skipping perms assertion"
fi

# ── list ────────────────────────────────────────────────────────────────────────
out="$(run list)"
[[ "$out" == *smoke*   ]] && ok "list: shows instance"        || err "list" "instance missing"
[[ "$out" == *vanilla* ]] && ok "list: shows vanilla"         || err "list:vanilla" "missing"
if command -v python3 >/dev/null 2>&1; then
    run list --json | python3 -c "import json,sys;d=json.load(sys.stdin);assert any(i['name']=='smoke' for i in d)" 2>/dev/null \
        && ok "list --json: valid, contains smoke" || err "list --json" "invalid or missing"
else
    note "python3 absent: skipping list --json parse"
fi

# ── config round-trip ───────────────────────────────────────────────────────────
run config smoke model "claude-opus-4-8" >/dev/null 2>&1
val="$(run config smoke model)"
[ "$val" = "claude-opus-4-8" ] && ok "config: write/read round-trip" || err "config" "got '$val'"

# ── clone (security: never copies credentials) ──────────────────────────────────
run add smoke2 >/dev/null 2>&1
printf '{"oauthToken":"SMOKETOKEN"}' > "$CLAUDECTL_BASE/smoke/.credentials.json"
run clone smoke smoke2 >/dev/null 2>&1
[ -f "$CLAUDECTL_BASE/smoke2/settings.json" ]        && ok "clone: settings.json copied" || err "clone:settings" "not copied"
[ ! -f "$CLAUDECTL_BASE/smoke2/.credentials.json" ]  && ok "clone: credentials NOT copied (security)" \
                                                     || err "clone:creds" "SECURITY VIOLATION"

# ── token (must print path only, never the secret value) ────────────────────────
tok_out="$(run token smoke 2>&1)"; code=$?
{ [ $code -eq 0 ] && [[ "$tok_out" == *.credentials.json* ]]; } && ok "token: prints credentials path" || err "token:path" "exit $code"
[[ "$tok_out" != *SMOKETOKEN* ]] && ok "token: does NOT leak the token value" || err "token:leak" "SECURITY VIOLATION: token value printed"
rm -f "$CLAUDECTL_BASE/smoke/.credentials.json"

# ── status ──────────────────────────────────────────────────────────────────────
run status >/dev/null 2>&1 && ok "status: exits 0" || err "status" "non-zero"
if command -v python3 >/dev/null 2>&1; then
    run status --json | python3 -c "import json,sys;assert isinstance(json.load(sys.stdin),list)" 2>/dev/null \
        && ok "status --json: valid array" || err "status --json" "invalid"
fi

# ── status: live process attribution (the real per-instance code path) ──────────
# Linux attributes a running CLAUDE_CONFIG_DIR process to its instance via procfs;
# macOS has no procfs and returns a clean empty result; skip elsewhere (Git Bash).
case "$(uname -s)" in
  Linux)
    CLAUDE_CONFIG_DIR="$CLAUDECTL_BASE/smoke" sleep 30 &
    _sp=$!; sleep 1
    sj="$(run status --json 2>/dev/null)"
    case "$sj" in
      *'"instance":"smoke"'*) ok "status: live process attributed to its instance" ;;
      *)                      err "status:attribution" "running smoke pid not attributed" ;;
    esac
    kill "$_sp" 2>/dev/null ;;
  Darwin)
    run status >/dev/null 2>&1 && ok "status: clean exit, no procfs (macOS)" || err "status:macos" "non-zero" ;;
  *)
    note "status live-attribution: skipped on $(uname -s)" ;;
esac

# ── spawn --dry-run must NOT execute ────────────────────────────────────────────
dry="$(run spawn smoke --dry-run 2>&1)"
[[ "$dry" == *claude-smoke* ]]       && ok "spawn --dry-run: prints launcher"  || err "spawn:dry-path" "launcher missing"
[[ "$dry" != *smoke-stub-claude* ]]  && ok "spawn --dry-run: did not execute"  || err "spawn:dry-exec" "executed!"

# ── spawn real exec (optional) ──────────────────────────────────────────────────
if [ "$REAL_EXEC" = "1" ]; then
    ver="$(run spawn smoke -- --version 2>&1)"; code=$?
    [ $code -eq 0 ] && ok "spawn -- --version: real exec exits 0" || err "spawn:real" "exit $code"
else
    note "real-claude mode off: skipping real spawn exec (set CLAUDECTL_SMOKE_REAL_CLAUDE=1)"
fi

# ── remove ──────────────────────────────────────────────────────────────────────
run remove smoke --force >/dev/null 2>&1
[ ! -f "$CLAUDECTL_BIN/claude-smoke" ] && ok "remove: launcher removed" || err "remove" "still present"

# ── Summary ─────────────────────────────────────────────────────────────────────
printf '\nsmoke: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && exit 0 || exit 1
