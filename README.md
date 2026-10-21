# agentic-quality-gate

**SonarQube replacement for PRs** — multi-language Semgrep hotspots, Sonar-style
duplication %, complexity, coverage, peer-style line comments.

**No AI.** Completely isolated from [`agentic-review`](https://github.com/pulumamidi-harsha/agentic-review).

## Two hubs (separate jobs)

| Folder / repo | Workflow job | Responsibility |
|---------------|--------------|----------------|
| **agentic-quality-gate** (this) | `PR Quality Gate` | Sonar replacement only |
| **agentic-review** | `AI PR Review` | AI review only |

Consumer repos add **two caller YAML files** if they want both — never one combined job.

## What it runs (PR-scoped)

- **Semgrep** (`semgrep` CLI) — language packs for top enterprise stacks + local hotspot rules (JS/TS, Python, Go, Java, Terraform, C#, Ruby, PHP, Docker, Bash, …)
- **jscpd** — block findings + **Duplication on New Code %** (Sonar default ≤ 3%)
- **Lizard** — cyclomatic complexity
- **Coverage** — when lcov/cobertura/istanbul reports exist
- Compact Failed-conditions summary + collapsed How-to-fix line comments

## Stacks covered (org-scale)

Language packs are selected from PR files. Common stacks include:

TypeScript/JavaScript/React/Node, Python (Django/Flask), Go, Java/Spring, Kotlin,
C#/.NET, Ruby/Rails, PHP, Rust, Scala, Swift, C/C++, Dart, Terraform, Docker,
Kubernetes/Helm, Ansible, CloudFormation, Bash, SQL, PowerShell, and more.

Registry packs that 404 are skipped per-pack; **local hotspot rules always run**.

## Caller (minimal)

See [`examples/caller-workflow.yml`](examples/caller-workflow.yml). Pin `uses:` and `pipeline_ref` to a **full SHA**.

## Policy

- Engines / packs: `config/packages/default.yml` + `config/packages/default/rules/`
- Pass/fail: `config/quality-gate.yml` (`AGENTIC_GATE_MODE=advisory|soft_fail|hard_fail`)
- Duplication density: `JSCPD_MAX_PCT_NEW_CODE` (default `3`)

## Fail-closed scanners

If Semgrep / jscpd / lizard is **enabled** and has PR code to scan, but install or
scan fails (no usable output), the **job fails** even in `advisory` mode — so an
empty scan is never treated as a clean PR. Intentional skips (docs-only PRs, no
code files) still pass.

## Skip

PR labels: `skip-quality-gate`, `skip-ai-review`, or `no-review`.
