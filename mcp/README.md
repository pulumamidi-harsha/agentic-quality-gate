# aqg-mcp — Cursor MCP for agentic-quality-gate

Exposes `run_quality_gate` to Cursor Agent so developers get the same
Semgrep / duplication % / complexity checks **before** opening a PR.

No admin rights. Tools cache under `~/.cache/agentic-quality-gate`.

Install via the hub script:

```bash
bash scripts/install-cursor.sh
```

Then restart Cursor and ask: **“Run the quality gate on my changes.”**
