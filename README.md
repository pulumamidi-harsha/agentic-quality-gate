# agentic-quality-gate

**SonarQube replacement for PRs** — multi-language Semgrep hotspots, Sonar-style
duplication %, complexity, coverage, peer-style line comments.

**No AI.** Completely isolated from [`agentic-review`](https://github.com/pulumamidi-harsha/agentic-review).

## Two hubs (separate jobs)

| Folder / repo | Workflow job | Responsibility |
|---------------|--------------|----------------|
| **agentic-quality-gate** (this) | `PR Quality Gate` | Sonar replacement only |
| **agentic-review** | `AI PR Review` | AI review only |

## IDE / during coding (Cursor) — recommended

Problem statement includes checks **while coding** in the **IDE**, not only after a PR.
Use Cursor’s Agent + MCP so setup stays **easy and admin-free** (everything under your home directory).

### Setup (once per laptop — no admin)

```bash
# from a clone of this hub
bash scripts/install-cursor.sh
# Restart Cursor
```

That copies the hub to `~/.cursor/agentic-quality-gate` and registers the MCP server in
`~/.cursor/mcp.json`. Tools cache under `~/.cache/agentic-quality-gate`.

### Daily use

In Cursor Agent, on any app repo:

> Run the quality gate on my changes

Agent calls MCP tool `run_quality_gate` → same Semgrep / duplication % / complexity
engines as PR CI → explains findings with What / Why / How to fix.

Optional: copy [`examples/cursor-skill/SKILL.md`](examples/cursor-skill/SKILL.md) into
the app’s `.cursor/skills/quality-gate/` so Agent auto-triggers on “pre-PR” asks.

### Why not a classic VS Code extension?

Corporate laptops often block marketplace installs or need admin. **MCP + Agent** is the
agentic path in the problem statement (explain / prioritize in chat) and installs with
user-space tools only (`uvx` / `pip --user` / home cache).

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
