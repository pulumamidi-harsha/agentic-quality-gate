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

# VS Code MCP config (servers key)
write_vscode_mcp() {
  local out_path="$1"
  mkdir -p "$(dirname "$out_path")"
  python3 - "$out_path" "$CMD" "$ARGS_JSON" "$DEST" <<'PY'
import json, sys
from pathlib import Path

out_path, command, args_json, hub = sys.argv[1:5]
args = json.loads(args_json)
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
path = Path(out_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(vscode, indent=2) + "\n", encoding="utf-8")
print(f"  VS Code MCP → {path}")
PY
}

mkdir -p "${DEST}/examples"
write_vscode_mcp "${DEST}/examples/vscode-mcp.json"

# When install-app.sh set AGENTIC_APP_ROOT: wire THIS app in one shot
APP_ROOT="${AGENTIC_APP_ROOT:-}"
if [[ -n "$APP_ROOT" && -d "$APP_ROOT/.git" ]]; then
  echo "  Wiring app repo: ${APP_ROOT}"
  write_vscode_mcp "${APP_ROOT}/.vscode/mcp.json"

  # Optional Cursor project skill (auto-hint for Agent)
  if [[ -f "${DEST}/examples/cursor-skill/SKILL.md" ]]; then
    mkdir -p "${APP_ROOT}/.cursor/skills/quality-gate"
    cp "${DEST}/examples/cursor-skill/SKILL.md" \
      "${APP_ROOT}/.cursor/skills/quality-gate/SKILL.md"
    echo "  Cursor skill → ${APP_ROOT}/.cursor/skills/quality-gate/SKILL.md"
  fi

  # pre-push hook — runs gate before every push (mandatory locally)
  HOOK_DIR="${APP_ROOT}/.git/hooks"
  HOOK="${HOOK_DIR}/pre-push"
  mkdir -p "$HOOK_DIR"
  if [[ -f "$HOOK" ]] && ! grep -q 'agentic-quality-gate' "$HOOK" 2>/dev/null; then
    cp "$HOOK" "${HOOK}.bak.$(date +%Y%m%d%H%M%S)"
    echo "  Backed up existing pre-push → ${HOOK}.bak.*"
  fi
  cat > "$HOOK" <<HOOK
#!/usr/bin/env bash
# agentic-quality-gate — block push when the local quality gate fails
set -euo pipefail
HUB="\${AGENTIC_QUALITY_GATE_HOME:-\$HOME/.cursor/agentic-quality-gate}"
RUN_QG="\${HUB}/scripts/run-qg.sh"
GATE="\${HUB}/scripts/local-gate.sh"
if [[ -f "\$RUN_QG" ]]; then
  echo "═══ agentic-quality-gate (pre-push) ═══"
  exec bash "\$RUN_QG" --base "\${AGENTIC_GATE_BASE:-main}" --strict
fi
if [[ ! -f "\$GATE" ]]; then
  echo "agentic-quality-gate: missing \$GATE — re-run install-app.sh" >&2
  exit 1
fi
echo "═══ agentic-quality-gate (pre-push) ═══"
exec bash "\$GATE" --base "\${AGENTIC_GATE_BASE:-main}" --strict
HOOK
  chmod +x "$HOOK"
  echo "  git pre-push hook → ${HOOK}"

  # VS Code: Terminal → Run Task → run-qg (live scrolling logs)
  if [[ -f "${DEST}/examples/vscode-tasks.json" ]]; then
    mkdir -p "${APP_ROOT}/.vscode"
    cp "${DEST}/examples/vscode-tasks.json" "${APP_ROOT}/.vscode/tasks.json"
    echo "  VS Code task → ${APP_ROOT}/.vscode/tasks.json  (Run Task → run-qg)"
  fi

  # PR CI workflow if missing (merge authority on GitHub)
  WF_DIR="${APP_ROOT}/.github/workflows"
  WF="${WF_DIR}/quality-gate.yml"
  if [[ ! -f "$WF" && -f "${DEST}/examples/caller-workflow.yml" ]]; then
    mkdir -p "$WF_DIR"
    cp "${DEST}/examples/caller-workflow.yml" "$WF"
    echo "  PR workflow → ${WF}  (commit this file; pin SHA before production)"
  fi
fi

# User-space CLI: typing `run-qg` in any terminal must work (no admin)
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
if [[ ! -f "${DEST}/scripts/run-qg.sh" ]]; then
  echo "error: missing ${DEST}/scripts/run-qg.sh — hub install incomplete" >&2
  exit 1
fi
chmod +x "${DEST}/scripts/run-qg.sh"
ln -sfn "${DEST}/scripts/run-qg.sh" "${BIN_DIR}/run-qg"
chmod +x "${BIN_DIR}/run-qg"
echo "  CLI → ${BIN_DIR}/run-qg"

# Ensure ~/.local/bin is on PATH for zsh/bash login shells (idempotent)
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
PATH_MARKER='# agentic-quality-gate: run-qg on PATH'
ensure_path_rc() {
  local rc="$1"
  [[ -f "$rc" ]] || touch "$rc"
  if grep -Fq "$PATH_MARKER" "$rc" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "$PATH_MARKER"
    echo "$PATH_LINE"
  } >> "$rc"
  echo "  PATH → added ~/.local/bin to ${rc}"
}
ensure_path_rc "${HOME}/.zshrc"
ensure_path_rc "${HOME}/.zprofile"
ensure_path_rc "${HOME}/.bashrc"
ensure_path_rc "${HOME}/.bash_profile"
# Fish (optional)
if [[ -d "${HOME}/.config/fish" ]]; then
  FISH_CFG="${HOME}/.config/fish/config.fish"
  FISH_MARKER="# agentic-quality-gate: run-qg on PATH"
  FISH_LINE='fish_add_path -g "$HOME/.local/bin"'
  touch "$FISH_CFG"
  if ! grep -Fq "$FISH_MARKER" "$FISH_CFG" 2>/dev/null; then
    {
      echo ""
      echo "$FISH_MARKER"
      echo "$FISH_LINE"
    } >> "$FISH_CFG"
    echo "  PATH → added ~/.local/bin to ${FISH_CFG}"
  fi
fi

# Verify the command resolves when PATH includes BIN_DIR
if PATH="${BIN_DIR}:$PATH" command -v run-qg >/dev/null 2>&1; then
  echo "  OK   → ~/.local/bin/run-qg installed"
else
  echo "  warn → run-qg symlink missing; try: ls -la ${BIN_DIR}/run-qg" >&2
fi

echo ""
echo "Done. No need to keep a separate clone of the hub."
if [[ -n "$APP_ROOT" ]]; then
  echo ""
  echo "This app is ready: ${APP_ROOT}"
  echo "  Type: run-qg"
else
  echo ""
  echo "Laptop hub installed. Wire an app with one paste:"
  echo "  cd /path/to/your-app && curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash && export PATH=\"\$HOME/.local/bin:\$PATH\" && hash -r"
fi
