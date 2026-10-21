#!/usr/bin/env bash
# One command from your APPLICATION repo — MCP + Agent + local push hook.
#
#   cd /path/to/dso-os-frontend   # (or any app)
#   curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash
#
# What it does:
#   1) Installs the hub under ~/.cursor/agentic-quality-gate (no manual clone)
#   2) Registers Cursor MCP + this app's .vscode/mcp.json
#   3) Puts `run-qg` on your PATH (~/.local/bin) so the terminal command works
#   4) Installs a git pre-push hook so the gate runs before every push
#
set -euo pipefail

RAW_BASE="${AGENTIC_QUALITY_GATE_RAW:-https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main}"

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "error: run this from inside your application git repo, e.g.:" >&2
  echo "  cd ~/code/dso-os-frontend" >&2
  echo "  curl -fsSL ${RAW_BASE}/scripts/install-app.sh | bash" >&2
  exit 2
fi

APP_ROOT="$(git rev-parse --show-toplevel)"
export AGENTIC_APP_ROOT="$APP_ROOT"

echo "═══ agentic-quality-gate → this app ═══"
echo "  App: ${APP_ROOT}"

# Prefer sibling install-ide.sh when this file lives in a hub checkout;
# otherwise fetch install-ide.sh (same one-liner UX when curled).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n "$HERE" && -f "${HERE}/install-ide.sh" ]]; then
  bash "${HERE}/install-ide.sh"
else
  curl -fsSL "${RAW_BASE}/scripts/install-ide.sh" | bash
fi

echo ""
echo "Done for this app."
echo "  Restart VS Code / Cursor on: ${APP_ROOT}"
echo "  Terminal (live logs):  run-qg"
echo "  VS Code: Terminal → Run Task → run-qg"
echo "  Agent chat: run-qg"
echo "  Push runs the gate automatically (pre-push). Skip once: git push --no-verify"
