#!/usr/bin/env bash
# One-command Cursor setup (no admin / no sudo).
# Installs hub into ~/.cursor/agentic-quality-gate and registers the MCP server.
set -euo pipefail

HUB_SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${AGENTIC_QUALITY_GATE_HOME:-$HOME/.cursor/agentic-quality-gate}"
MCP_JSON="${HOME}/.cursor/mcp.json"
UVX="${UVX:-}"

echo "═══ agentic-quality-gate → Cursor (user-space) ═══"
echo "  Source: ${HUB_SRC}"
echo "  Dest:   ${DEST}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required (user install / Xcode CLT / pyenv — no admin needed if already present)" >&2
  exit 1
fi

# Prefer uvx when available (also user-space via curl install)
if [[ -z "$UVX" ]]; then
  if command -v uvx >/dev/null 2>&1; then
    UVX="$(command -v uvx)"
  elif [[ -x "${HOME}/.local/bin/uvx" ]]; then
    UVX="${HOME}/.local/bin/uvx"
  fi
fi

mkdir -p "$(dirname "$DEST")"
# Sync hub into user Cursor dir (no root)
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git' \
    --exclude '.agentic-quality-gate' \
    --exclude 'mcp/.venv' \
    "${HUB_SRC}/" "${DEST}/"
else
  rm -rf "${DEST}"
  mkdir -p "${DEST}"
  cp -R "${HUB_SRC}/." "${DEST}/"
  rm -rf "${DEST}/.git" "${DEST}/.agentic-quality-gate" "${DEST}/mcp/.venv"
fi

mkdir -p "${HOME}/.cursor"
mkdir -p "${HOME}/.cache/agentic-quality-gate"

# Build MCP server args
if [[ -n "$UVX" ]]; then
  CMD="$UVX"
  # shellcheck disable=SC2016
  ARGS_JSON=$(python3 - <<PY
import json
print(json.dumps([
  "--from", "${DEST}/mcp",
  "aqg-mcp",
]))
PY
)
  echo "  Runner: uvx (recommended)"
else
  CMD="python3"
  ARGS_JSON=$(python3 - <<PY
import json
print(json.dumps(["${DEST}/mcp/aqg_mcp/server.py"]))
PY
)
  echo "  Runner: python3 (install MCP deps into user env on first Cursor start if needed)"
  # Best-effort: user-site install of mcp (no sudo)
  python3 -m pip install --user -q "mcp>=1.2.0,<2" 2>/dev/null || \
    echo "  note: could not pip install mcp --user; Cursor may still work if mcp is available"
fi

python3 - "$MCP_JSON" "$CMD" "$ARGS_JSON" "$DEST" <<'PY'
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
print(f"  Wrote MCP entry → {path}")
PY

# Project skill template for teams who want Agent auto-behavior in a repo
SKILL_SRC="${DEST}/examples/cursor-skill/SKILL.md"
SKILL_HINT="${DEST}/examples/cursor-skill"
echo ""
echo "Done. Next steps (developer — no admin):"
echo "  1. Restart Cursor"
echo "  2. Open your app repo"
echo "  3. Ask Agent:  Run the quality gate on my changes"
echo ""
echo "Optional — copy skill into an app repo for auto-triggers:"
echo "  mkdir -p .cursor/skills/quality-gate"
echo "  cp ${SKILL_HINT}/SKILL.md .cursor/skills/quality-gate/"
echo ""
echo "MCP config: ${MCP_JSON}"
echo "Hub home:   ${DEST}"
