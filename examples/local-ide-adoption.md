# IDE adoption — MCP + Agent

One path for every developer: **MCP + Agent**. No repo clone. No admin. No marketplace extension.

## Once per laptop

```bash
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-ide.sh | bash
```

Restart Cursor or VS Code.

## Every day

1. Open your **app** repo.
2. Ask Agent: `Run the quality gate on my changes`
3. Fix findings in chat (what / why / how to fix).

**VS Code only:** once per app, copy  
`~/.cursor/agentic-quality-gate/examples/vscode-mcp.json` → `.vscode/mcp.json`, then restart.

## Optional (Cursor): auto-hint in an app

```bash
mkdir -p .cursor/skills/quality-gate
cp ~/.cursor/agentic-quality-gate/examples/cursor-skill/SKILL.md \
  .cursor/skills/quality-gate/
```

## Keep PR CI

Do not remove `.github/workflows/quality-gate.yml`. Local MCP is early feedback; PR CI is merge authority.

## Pilot checklist

- [ ] Ran `curl … install-ide.sh | bash` once + restarted IDE
- [ ] Asked Agent: “Run the quality gate on my changes”
- [ ] (VS Code) App has `.vscode/mcp.json` from the install template
- [ ] PR workflow still pinned to a hub SHA
