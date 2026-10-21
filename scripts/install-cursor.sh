#!/usr/bin/env bash
# Back-compat wrapper — use install-ide.sh (works for Cursor and VS Code).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "${HERE}/install-ide.sh" "$@"
