# agentic-quality-gate

SonarQube replacement for pull requests: Semgrep hotspots, duplication %, complexity, coverage, and peer-style PR comments.

**No AI in this hub.** AI review lives in a separate repo: [`agentic-review`](https://github.com/pulumamidi-harsha/agentic-review).

| Hub | Job | What it does |
|-----|-----|--------------|
| **agentic-quality-gate** (this) | `PR Quality Gate` | Sonar-style quality checks |
| **agentic-review** | `AI PR Review` | AI review only |

---

## For developers — one command per app

Use **MCP + Agent** in Cursor or VS Code. **Do not clone this hub.**

From your **application** repo (example: `dso-os-frontend`):

```bash
cd /path/to/dso-os-frontend
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash
```

That single command:

1. Installs the hub under `~/.cursor/agentic-quality-gate`
2. Registers Cursor MCP
3. Writes `.vscode/mcp.json` in **this** app (VS Code ready)
4. Installs a **git pre-push hook** so the gate runs before every push
5. Adds the PR workflow file if missing (`.github/workflows/quality-gate.yml`)

Then **restart** the IDE on that app folder and ask Agent:

```text
Run the quality gate on my changes
```

Agent streams a live log in chat (like a build), then explains findings (what / why / how to fix).

### Another app later?

Same one-liner from that repo’s root. No extra copy/paste steps.

### Push / PR (automatic)

| When | What runs |
|------|-----------|
| **git push** | Local pre-push hook → same engines as CI (`--strict`) |
| **Pull request** | GitHub `PR Quality Gate` workflow (merge authority) |

Skip the local hook once (not recommended): `git push --no-verify`.  
CI on the PR still runs. Pin the workflow `uses:` / `pipeline_ref` to a **full SHA** before production.

---

## What runs where

| Check | IDE (MCP + Agent) | git push (hook) | GitHub PR |
|-------|-------------------|-----------------|-----------|
| Semgrep hotspots | yes | yes | yes |
| Duplication % | yes | yes | yes |
| Complexity | yes | yes | yes |
| Coverage | no | no | when `lcov` is present |
| Line comments on the PR | no (chat) | no | yes |

Languages and stacks: TypeScript/JavaScript/React/Node, Python, Go, Java/Spring, Kotlin, C#, Ruby, PHP, Rust, Terraform, Docker, Kubernetes/Helm, Ansible, Bash, SQL, and more.

Policy: `config/packages/default.yml`, `config/packages/default/rules/`, `config/quality-gate.yml` (`AGENTIC_GATE_MODE=advisory|soft_fail|hard_fail`). CI fails closed if an enabled scanner cannot run.

Skip labels (CI): `skip-quality-gate`, `skip-ai-review`, or `no-review`.
