# IDE adoption (Cursor) — app repos

Goal: developers see quality-gate findings **before** opening a PR, with
**almost no setup pain** and **no admin rights**.

## Recommended (all developers)

### 1. One-time laptop setup

```bash
git clone https://github.com/pulumamidi-harsha/agentic-quality-gate.git
cd agentic-quality-gate
bash scripts/install-cursor.sh
# Restart Cursor
```

- Installs under `~/.cursor/agentic-quality-gate` (user home)
- Registers MCP in `~/.cursor/mcp.json`
- Caches tools under `~/.cache/agentic-quality-gate`
- No `sudo`, no corporate marketplace extension

### 2. Daily use

Open your app (e.g. `dso-os-frontend`) in Cursor and ask Agent:

> Run the quality gate on my changes

Agent uses MCP `run_quality_gate` → Semgrep hotspots, duplication %, complexity
→ explains What / Why / How to fix.

### 3. Optional auto-trigger in a repo

```bash
mkdir -p .cursor/skills/quality-gate
cp /path/to/agentic-quality-gate/examples/cursor-skill/SKILL.md \
  .cursor/skills/quality-gate/
```

### 4. Keep PR CI

Do **not** remove `.github/workflows/quality-gate.yml`. CI remains merge authority.

## Pilot checklist (`dso-os-frontend`)

- [ ] Each developer ran `install-cursor.sh` once + restarted Cursor
- [ ] Ask Agent: “Run the quality gate on my changes” on a branch with the seed file
- [ ] Optional: commit `.cursor/skills/quality-gate/SKILL.md`
- [ ] PR workflow still pinned to hub SHA

## What is covered vs PR CI

| Check | Cursor MCP | PR CI |
|-------|------------|-------|
| Semgrep hotspots | yes | yes |
| Duplication % | yes | yes |
| Complexity | yes | yes |
| Coverage | no | when lcov present |
| PR comments | no (chat) | yes |

## Advanced (not required)

- CLI: `scripts/local-gate.sh`
- pre-commit: `examples/pre-commit-config.yaml`
- VS Code tasks: `examples/vscode-tasks.json`
