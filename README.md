# agentic-quality-gate

SonarQube replacement for pull requests: Semgrep hotspots, duplication %, complexity, coverage, and peer-style PR comments.

**No AI in this hub.** AI review lives in a separate repo: [`agentic-review`](https://github.com/pulumamidi-harsha/agentic-review).

| Hub | Job | What it does |
|-----|-----|--------------|
| **agentic-quality-gate** (this) | `PR Quality Gate` | Sonar-style quality checks |
| **agentic-review** | `AI PR Review` | AI review only |

---

## For developers: check quality in your IDE

Use **MCP + Agent** (Cursor or VS Code). One install. No admin. **Do not clone this repo.**

### Step 1 — Install once (any laptop)

```bash
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-ide.sh | bash
```

Then **restart** your IDE.

### Step 2 — Run the gate on your app

Open your **application** repo (not this hub). In Agent chat, say:

```text
Run the quality gate on my changes
```

| IDE | Extra step (once per app, VS Code only) |
|-----|----------------------------------------|
| **Cursor** | None — MCP is already registered |
| **VS Code** | Copy `~/.cursor/agentic-quality-gate/examples/vscode-mcp.json` to your app’s `.vscode/mcp.json`, then restart |

### Step 3 — Fix what Agent reports

Agent calls the quality-gate MCP tool and explains findings (what / why / how to fix). Same engines as PR CI for Semgrep, duplication %, and complexity. Coverage stays CI-only.

To update the install later, run the same `curl … | bash` again.

---

## For app repos: PR CI (merge authority)

Add a thin workflow that calls this hub — see [`examples/caller-workflow.yml`](examples/caller-workflow.yml).

Pin `uses:` and `pipeline_ref` to a **full commit SHA**. Keep that workflow even when developers use MCP locally; GitHub remains the merge authority.

Skip labels (CI): `skip-quality-gate`, `skip-ai-review`, or `no-review`.

---

## What runs where

| Check | IDE (MCP + Agent) | GitHub PR |
|-------|-------------------|-----------|
| Semgrep hotspots | yes | yes |
| Duplication % | yes | yes |
| Complexity | yes | yes |
| Coverage | no | when `lcov` is present |
| Line comments on the PR | no (chat only) | yes |

Languages and stacks: TypeScript/JavaScript/React/Node, Python, Go, Java/Spring, Kotlin, C#, Ruby, PHP, Rust, Terraform, Docker, Kubernetes/Helm, Ansible, Bash, SQL, and more.

Policy lives in `config/packages/default.yml`, `config/packages/default/rules/`, and `config/quality-gate.yml` (`AGENTIC_GATE_MODE=advisory|soft_fail|hard_fail`). CI fails closed if an enabled scanner cannot run.
