# agentic-quality-gate

**SonarQube replacement for PRs** — Semgrep hotspots, complexity, duplication, coverage, peer-style line comments.

**No AI.** Completely isolated from [`agentic-review`](https://github.com/pulumamidi-harsha/agentic-review).

## Two hubs (separate jobs)

| Folder / repo | Workflow job | Responsibility |
|---------------|--------------|----------------|
| **agentic-quality-gate** (this) | `PR Quality Gate` | Sonar replacement only |
| **agentic-review** | `AI PR Review` | AI review only |

Consumer repos add **two caller YAML files** if they want both — never one combined job.

## What it runs (PR-scoped)

- Semgrep (language packs + package rules: eval, XSS, secrets, cmd injection, …)
- jscpd (duplication)
- Lizard (complexity)
- Coverage gate (when reports exist)
- Failed-conditions summary + collapsed How-to-fix line comments

## Caller (minimal)

See [`examples/caller-workflow.yml`](examples/caller-workflow.yml). Pin `uses:` and `pipeline_ref` to a **full SHA**.

## Policy

- Engines / packs: `config/packages/default.yml` + `config/packages/default/rules/`
- Pass/fail: `config/quality-gate.yml` (`AGENTIC_GATE_MODE=advisory|soft_fail|hard_fail`)

## Skip

PR labels: `skip-quality-gate`, `skip-ai-review`, or `no-review`.
