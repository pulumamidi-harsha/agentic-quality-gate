# agentic-quality-gate

SonarQube replacement for pull requests: Semgrep hotspots, duplication %, complexity, coverage, and peer-style PR comments.

**No AI in this hub.** AI review lives in a separate repo: [`agentic-review`](https://github.com/pulumamidi-harsha/agentic-review).

| Hub | Job | What it does |
|-----|-----|--------------|
| **agentic-quality-gate** (this) | `PR Quality Gate` | Sonar-style quality checks |
| **agentic-review** | `AI PR Review` | AI review only |

---

## For developers — one command per app

From your application repo (example: `dso-os-frontend`), paste **one line**.

**If you already have this hub next to the app** (works offline / avoids SSL issues):

```bash
cd /path/to/dso-os-frontend && bash ../agentic-quality-gate/scripts/install-app.sh && export PATH="$HOME/.local/bin:$PATH" && hash -r
```

**Or download from GitHub** (needs working HTTPS to GitHub):

```bash
cd /path/to/dso-os-frontend && curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash && export PATH="$HOME/.local/bin:$PATH" && hash -r
```

If `curl` fails with a TLS / LibreSSL error, use the local `bash ../agentic-quality-gate/...` line above (or `git clone` the hub once, then that line).

That installs everything and enables `run-qg` **in the same terminal**. Future terminals get PATH from your shell config automatically.

### Run in the terminal (recommended — live scrolling logs)

```bash
run-qg
```

In **VS Code**: `Terminal → Run Task… → run-qg` (same live log in the Terminal panel).

First run can take a few minutes (Semgrep install + rule packs). Later runs reuse `~/.cache/agentic-quality-gate` and are faster. You will see lines like `→ semgrep`, pack names, etc. while it works.

### Run in Agent chat (short)

```text
run-qg
```

Chat is good for **explain / fix** after the scan. Some Copilot/Agent UIs stay quiet until a tool call returns — for a npm-style live feed, use the **terminal** command above.

### Push / PR (automatic)

| When | What runs |
|------|-----------|
| **git push** | Local pre-push hook (`run-qg --strict`) |
| **Pull request** | GitHub `PR Quality Gate` (merge authority) |

Skip local hook once (not recommended): `git push --no-verify`.  
Pin workflow `uses:` / `pipeline_ref` to a **full SHA** before production.

---

## What runs where

| Check | Terminal / chat | git push | GitHub PR |
|-------|-----------------|----------|-----------|
| Semgrep hotspots | yes | yes | yes |
| Duplication % | yes | yes | yes |
| Complexity | yes | yes | yes |
| Coverage | no | no | when `lcov` is present |
| Line comments on the PR | no | no | yes |

Languages and stacks: TypeScript/JavaScript/React/Node, Python, Go, Java/Spring, Kotlin, C#, Ruby, PHP, Rust, Terraform, Docker, Kubernetes/Helm, Ansible, Bash, SQL, and more.

Policy: `config/packages/default.yml`, `config/packages/default/rules/`, `config/quality-gate.yml`. CI fails closed if an enabled scanner cannot run.

Skip labels (CI): `skip-quality-gate`, `skip-ai-review`, or `no-review`.
