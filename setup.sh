#!/usr/bin/env bash
# setup.sh — install claudectl on Linux / macOS
set -euo pipefail

DEST="${CLAUDECTL_BIN:-$HOME/.local/bin}"
SRC="$(cd "$(dirname "$0")" && pwd)/scripts/claudectl"

[ -f "$SRC" ] || { printf 'error: scripts/claudectl not found — run from the repo root\n' >&2; exit 1; }

# Check for Claude Code
if ! command -v claude >/dev/null 2>&1 && [ ! -f "$DEST/claude" ]; then
    printf 'warning: Claude Code not found at %s or in PATH\n' "$DEST"
    printf '  Install Claude Code first: https://claude.ai/download\n'
    printf '  Then re-run: bash setup.sh\n\n'
fi

mkdir -p "$DEST"
cp "$SRC" "$DEST/claudectl"
chmod +x "$DEST/claudectl"
printf 'installed claudectl to %s\n' "$DEST/claudectl"

# Idempotent PATH setup
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$DEST"; then
    line="export PATH=\"$DEST:\$PATH\""
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$rc" ] && ! grep -qF "$DEST" "$rc"; then
            printf '\n# added by claudectl setup.sh\n%s\n' "$line" >> "$rc"
            printf 'added %s to PATH in %s\n' "$DEST" "$rc"
        fi
    done
    printf 'open a new terminal (or run: source ~/.bashrc) to activate\n'
else
    printf '%s is already in PATH\n' "$DEST"
fi

printf '\nclaudectl is ready. Run: claudectl help\n'
