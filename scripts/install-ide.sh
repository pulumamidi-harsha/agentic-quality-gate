#!/usr/bin/env bash
# Simplest IDE setup — no manual clone, no admin.
#
# Cursor / VS Code (Copilot MCP):
#   curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-ide.sh | bash
#
# Or from a local clone of this hub:
#   bash scripts/install-ide.sh
#
# Installs into ~/.cursor/agentic-quality-gate and registers MCP.
set -euo pipefail

REPO_URL="${AGENTIC_QUALITY_GATE_REPO:-https://github.com/pulumamidi-harsha/agentic-quality-gate.git}"
REPO_REF="${AGENTIC_QUALITY_GATE_REF:-main}"
DEST="${AGENTIC_QUALITY_GATE_HOME:-$HOME/.cursor/agentic-quality-gate}"
CURSOR_MCP="${HOME}/.cursor/mcp.json"
VSCODE_MCP_EXAMPLE="${HOME}/.cursor/agentic-quality-gate/examples/vscode-mcp.json"
UVX="${UVX:-}"

echo "═══ agentic-quality-gate → IDE (Cursor / VS Code) ═══"
echo "  Dest: ${DEST}"
echo "  Ref:  ${REPO_REF}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required (already on most Macs; else user-space pyenv — no admin)" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "error: git required" >&2
  exit 1
fi

# Resolve optional local source (when script lives inside a clone)
LOCAL_SRC=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  _here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -f "${_here}/scripts/local-gate.sh" ]]; then
    LOCAL_SRC="${_here}"
  fi
fi

mkdir -p "$(dirname "$DEST")" "${HOME}/.cursor" "${HOME}/.cache/agentic-quality-gate"

# Prefer git clone/pull into DEST so users never manage a working copy themselves.
# If DEST already exists as a git repo, pull. Else clone. Optional: seed from LOCAL_SRC once.
if [[ -d "${DEST}/.git" ]]; then
  echo "  Updating existing install…"
  git -C "$DEST" fetch --depth=1 origin "$REPO_REF" 2>/dev/null || git -C "$DEST" fetch --depth=1 origin
  git -C "$DEST" checkout -q FETCH_HEAD 2>/dev/null || git -C "$DEST" pull --ff-only origin "$REPO_REF" || true
elif [[ -n "$LOCAL_SRC" && "$LOCAL_SRC" != "$DEST" ]]; then
  echo "  Installing from local clone → ${DEST}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '.agentic-quality-gate' \
      --exclude 'mcp/.venv' \
      "${LOCAL_SRC}/" "${DEST}/"
  else
    rm -rf "${DEST}"
    mkdir -p "${DEST}"
    cp -R "${LOCAL_SRC}/." "${DEST}/"
  fi
  # Turn into a shallow git clone for future self-updates when possible
  if [[ ! -d "${DEST}/.git" ]]; then
    git -C "$DEST" init -q
    git -C "$DEST" remote add origin "$REPO_URL" 2>/dev/null || true
  fi
else
  echo "  Cloning ${REPO_URL} (${REPO_REF})…"
  rm -rf "${DEST}"
  git clone --depth=1 --branch "$REPO_REF" "$REPO_URL" "$DEST" \
    || git clone --depth=1 "$REPO_URL" "$DEST"
fi

if [[ ! -f "${DEST}/scripts/local-gate.sh" ]]; then
  echo "error: install incomplete — missing scripts/local-gate.sh under ${DEST}" >&2
  exit 1
fi

if [[ -z "$UVX" ]]; then
  if command -v uvx >/dev/null 2>&1; then
    UVX="$(command -v uvx)"
  elif [[ -x "${HOME}/.local/bin/uvx" ]]; then
    UVX="${HOME}/.local/bin/uvx"
  fi
fi

# Auto-install uv into user home if missing (no admin)
if [[ -z "$UVX" ]]; then
  echo "  Installing uv (user-space) for MCP runner…"
  curl -fsSL https://astral.sh/uv/install.sh | sh
  if [[ -x "${HOME}/.local/bin/uvx" ]]; then
    UVX="${HOME}/.local/bin/uvx"
  elif command -v uvx >/dev/null 2>&1; then
    UVX="$(command -v uvx)"
  fi
fi

if [[ -n "$UVX" ]]; then
  CMD="$UVX"
  ARGS_JSON=$(python3 - <<PY
import json
print(json.dumps(["--from", "${DEST}/mcp", "aqg-mcp"]))
PY
)
  echo "  Runner: uvx"
else
  CMD="python3"
  ARGS_JSON=$(python3 - <<PY
import json
print(json.dumps(["${DEST}/mcp/aqg_mcp/server.py"]))
PY
)
  echo "  Runner: python3"
  python3 -m pip install --user -q "mcp>=1.2.0,<2" 2>/dev/null || true
fi

# Cursor: ~/.cursor/mcp.json (mcpServers)
python3 - "$CURSOR_MCP" "$CMD" "$ARGS_JSON" "$DEST" <<'PY'
import json, sys
from pathlib import Path

mcp_path, command, args_json, hub = sys.argv[1:5]
args = json.loads(args_json)
path = Path(mcp_path)
data = {"mcpServers": {}}
if path.is_file():
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        data = {"mcpServers": {}}
if not isinstance(data.get("mcpServers"), dict):
    data["mcpServers"] = {}
data["mcpServers"]["agentic-quality-gate"] = {
    "command": command,
    "args": args,
    "env": {
        "AGENTIC_QUALITY_GATE_HOME": hub,
        "AGENTIC_QUALITY_GATE_CACHE": str(Path.home() / ".cache" / "agentic-quality-gate"),
    },
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"  Cursor MCP → {path}")
PY

# VS Code template (servers key) for apps / user to copy
mkdir -p "${DEST}/examples"
python3 - "$DEST" "$CMD" "$ARGS_JSON" <<'PY'
import json, sys
from pathlib import Path
dest, command, args_json = sys.argv[1:4]
args = json.loads(args_json)
hub = dest
vscode = {
    "servers": {
        "agentic-quality-gate": {
            "type": "stdio",
            "command": command,
            "args": args,
            "env": {
                "AGENTIC_QUALITY_GATE_HOME": hub,
                "AGENTIC_QUALITY_GATE_CACHE": str(Path.home() / ".cache" / "agentic-quality-gate"),
            },
        }
    }
}
out = Path(dest) / "examples" / "vscode-mcp.json"
out.write_text(json.dumps(vscode, indent=2) + "\n", encoding="utf-8")
print(f"  VS Code template → {out}")
PY

echo ""
echo "Done. No need to keep a separate clone of this repo."
echo ""
echo "Cursor:"
echo "  1. Restart Cursor"
echo "  2. Open your app repo"
echo "  3. Ask Agent:  Run the quality gate on my changes"
echo ""
echo "VS Code (+ Copilot Chat / MCP):"
echo "  1. Copy ${DEST}/examples/vscode-mcp.json → your app's .vscode/mcp.json"
echo "     (or: MCP: Add Server → Command → use the same uvx args)"
echo "  2. Restart VS Code"
echo "  3. In Copilot Chat (Agent):  Run the quality gate on my changes"
echo ""
echo "Update later (optional):"
echo "  curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-ide.sh | bash"
