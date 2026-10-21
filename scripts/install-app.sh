#!/usr/bin/env bash
# One paste from your APPLICATION repo — MCP + Agent + CLI + push hook.
#
#   cd /path/to/your-app && curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash && export PATH="$HOME/.local/bin:$PATH" && hash -r
#
# The trailing export/hash-r is required so `run-qg` works in THIS terminal
# immediately (curl|bash cannot change the parent shell by itself).
#
# What it does:
#   1) Installs the hub under ~/.cursor/agentic-quality-gate (no manual clone)
#   2) Registers Cursor MCP + this app's .vscode/mcp.json
#   3) Installs ~/.local/bin/run-qg and writes PATH into shell rc files
#   4) Installs a git pre-push hook so the gate runs before every push
#
set -euo pipefail

RAW_BASE="${AGENTIC_QUALITY_GATE_RAW:-https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main}"

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "error: run this from inside your application git repo, e.g.:" >&2
  echo "  cd ~/code/dso-os-frontend" >&2
  echo "  cd /path/to/your-app && curl -fsSL ${RAW_BASE}/scripts/install-app.sh | bash && export PATH=\"\$HOME/.local/bin:\$PATH\" && hash -r" >&2
  exit 2
fi

APP_ROOT="$(git rev-parse --show-toplevel)"
export AGENTIC_APP_ROOT="$APP_ROOT"

echo "═══ agentic-quality-gate → this app ═══"
echo "  App: ${APP_ROOT}"

# Prefer local hub scripts (no network). Else try curl; else git clone.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
REPO_URL="${AGENTIC_QUALITY_GATE_REPO:-https://github.com/pulumamidi-harsha/agentic-quality-gate.git}"
DEST="${AGENTIC_QUALITY_GATE_HOME:-$HOME/.cursor/agentic-quality-gate}"

run_install_ide() {
  local ide="$1"
  bash "$ide"
}

if [[ -n "$HERE" && -f "${HERE}/install-ide.sh" ]]; then
  run_install_ide "${HERE}/install-ide.sh"
elif [[ -f "${DEST}/scripts/install-ide.sh" ]]; then
  echo "  Using existing hub at ${DEST}"
  run_install_ide "${DEST}/scripts/install-ide.sh"
elif curl -fsSL "${RAW_BASE}/scripts/install-ide.sh" | bash; then
  :
else
  echo "  curl to GitHub raw failed (common on some Mac/LibreSSL setups)."
  echo "  Falling back to git clone → ${DEST}"
  mkdir -p "$(dirname "$DEST")"
  if [[ -d "${DEST}/.git" ]]; then
    git -C "$DEST" pull --ff-only || true
  else
    rm -rf "$DEST"
    git clone --depth=1 "$REPO_URL" "$DEST"
  fi
  run_install_ide "${DEST}/scripts/install-ide.sh"
fi

echo ""
echo "Done for this app: ${APP_ROOT}"
echo "  Type:  run-qg"
echo "  (If you used the full one-liner from the README, run-qg works in this terminal now.)"
echo "  VS Code: Run Task → run-qg · Agent chat: run-qg · push runs the gate automatically"
