# agentic-quality-gate

**SonarQube replacement for PRs** — Semgrep hotspots, complexity, duplication, coverage, peer-style line comments.

No AI. Roll out independently from [`agentic-review`](https://github.com/pulumamidi-harsha/agentic-review) (AI code review).

## Two hubs

| Repo | Purpose | Roll out when |
|------|---------|----------------|
| **agentic-quality-gate** (this) | Quality gate / Sonar replacement | You want PR SAST + metrics without AI |
| **agentic-review** | AI PR review (+ optional scans) | You want LLM review / Pass 1–2 |

Call either or both from a consumer repo with separate thin workflows.

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
