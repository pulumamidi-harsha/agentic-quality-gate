# agentic-quality-gate

**SonarQube replacement for PRs** — multi-language Semgrep hotspots, Sonar-style
duplication %, complexity, coverage, peer-style line comments.

**No AI.** Completely isolated from [`agentic-review`](https://github.com/pulumamidi-harsha/agentic-review).

## Two hubs (separate jobs)

| Folder / repo | Workflow job | Responsibility |
|---------------|--------------|----------------|
| **agentic-quality-gate** (this) | `PR Quality Gate` | Sonar replacement only |
| **agentic-review** | `AI PR Review` | AI review only |

## IDE / during coding — recommended (Cursor or VS Code)

Problem statement includes checks **while coding** in the **IDE**. Use **Agent + MCP**
(futuristic, explains findings in chat). No admin. **You do not need to clone this repo.**

### Setup (once per laptop)

```bash
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-ide.sh | bash
```

- Installs under `~/.cursor/agentic-quality-gate` (auto git clone/update)
- Registers Cursor MCP in `~/.cursor/mcp.json`
- Writes VS Code template at `~/.cursor/agentic-quality-gate/examples/vscode-mcp.json`
- Cache: `~/.cache/agentic-quality-gate`

### Daily use

| IDE | What to do |
|-----|------------|
| **Cursor** | Restart → open app repo → ask Agent: `Run the quality gate on my changes` |
| **VS Code** | Copy `examples/vscode-mcp.json` → app `.vscode/mcp.json` → restart → Copilot Chat (Agent): same ask |

Same engines as PR CI (Semgrep, duplication %, complexity). Coverage stays CI-only.

### Why MCP + Agent (not a classic marketplace extension)?

Corporate laptops often block extensions or need admin. MCP runs user-space and matches
the problem statement (explain / prioritize in chat).

## PR CI (merge authority)

Thin caller in each app — see [`examples/caller-workflow.yml`](examples/caller-workflow.yml).
Pin `uses:` and `pipeline_ref` to a **full SHA**.

## What it runs

| Surface | Semgrep | Duplication % | Complexity | Coverage |
|---------|---------|---------------|------------|----------|
| Cursor MCP / local | yes | yes | yes | no (CI-only) |
| GitHub PR workflow | yes | yes | yes | when lcov present |

Stacks: TypeScript/JavaScript/React/Node, Python, Go, Java/Spring, Kotlin, C#, Ruby, PHP,
Rust, Terraform, Docker, Kubernetes/Helm, Ansible, Bash, SQL, and more.

## Policy

- Engines: `config/packages/default.yml` + `config/packages/default/rules/`
- Pass/fail: `config/quality-gate.yml` (`AGENTIC_GATE_MODE=advisory|soft_fail|hard_fail`)
- Fail-closed in CI if an enabled scanner cannot run

## Advanced (optional)

Power users / automation can still call [`scripts/local-gate.sh`](scripts/local-gate.sh)
or [`examples/pre-commit-config.yaml`](examples/pre-commit-config.yaml). Not required for
normal Cursor developers.

## Skip (CI)

PR labels: `skip-quality-gate`, `skip-ai-review`, or `no-review`.
