#!/usr/bin/env bash
# Live quality gate in the terminal (scrollable logs — not silent like chat).
#
# From any app repo:
#   run-qg
#   bash ~/.cursor/agentic-quality-gate/scripts/run-qg.sh
#   bash ~/.cursor/agentic-quality-gate/scripts/run-qg.sh --strict
#
set -euo pipefail

HUB="${AGENTIC_QUALITY_GATE_HOME:-$HOME/.cursor/agentic-quality-gate}"
GATE="${HUB}/scripts/local-gate.sh"

if [[ ! -f "$GATE" ]]; then
  echo "error: quality gate not installed." >&2
  echo "  cd to your app and run:" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash" >&2
  exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "error: cd into your application git repo first" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

echo "═══ run-qg (terminal) ═══"
echo "  Repo: ${ROOT}"
echo "  Hub:  ${HUB}"
echo "  Tip:  first run can take a few minutes (Semgrep install + packs)."
echo "        Later runs reuse ~/.cache/agentic-quality-gate"
echo ""

# Human-readable live logs (no --json). Pass-through args: --strict --staged --base …
export PYTHONUNBUFFERED=1
if command -v stdbuf >/dev/null 2>&1; then
  exec stdbuf -oL -eL bash "$GATE" "$@"
fi
exec bash "$GATE" "$@"
