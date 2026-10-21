# aqg-mcp — MCP server for agentic-quality-gate

Exposes `run_quality_gate` to Cursor / VS Code Agent so developers get Semgrep,
duplication %, and complexity checks **before** opening a PR.

## Install (developers)

Do not clone this repo. One command:

```bash
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-ide.sh | bash
```

Restart the IDE, open your app repo, ask Agent:

```text
Run the quality gate on my changes
```

Full steps: [../README.md](../README.md).
