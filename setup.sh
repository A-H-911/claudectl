#!/usr/bin/env bash
# setup.sh — install claudectl on Linux / macOS
set -euo pipefail

DEST="${CLAUDECTL_BIN:-$HOME/.local/bin}"
SRC="$(cd "$(dirname "$0")" && pwd)/scripts/claudectl"

[ -f "$SRC" ] || { printf 'error: scripts/claudectl not found — run from the repo root\n' >&2; exit 1; }

mkdir -p "$DEST"
cp "$SRC" "$DEST/claudectl"
chmod +x "$DEST/claudectl"
printf 'installed claudectl to %s\n\n' "$DEST/claudectl"

# Delegate PATH wiring + verification to the installed CLI (single source of truth).
# CLAUDECTL_BIN is exported so the child uses the same install dir as $DEST.
CLAUDECTL_BIN="$DEST" bash "$DEST/claudectl" setup
