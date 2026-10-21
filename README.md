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

## Local / IDE (before the PR)

Same engines as CI (Semgrep, duplication %, complexity) — run while coding so
findings show up **before** you open a PR. Coverage stays CI-only.

```bash
# from your application repo
export AGENTIC_QUALITY_GATE_HOME=/path/to/agentic-quality-gate
bash "$AGENTIC_QUALITY_GATE_HOME/scripts/local-gate.sh"
bash "$AGENTIC_QUALITY_GATE_HOME/scripts/local-gate.sh" --staged    # pre-commit
bash "$AGENTIC_QUALITY_GATE_HOME/scripts/local-gate.sh" --strict    # exit 1 on findings
```

| Integration | Example |
|-------------|---------|
| Terminal / Cursor | `scripts/local-gate.sh` |
| VS Code / Cursor task | [`examples/vscode-tasks.json`](examples/vscode-tasks.json) |
| pre-commit | [`examples/pre-commit-config.yaml`](examples/pre-commit-config.yaml) |
| App adoption guide | [`examples/local-ide-adoption.md`](examples/local-ide-adoption.md) |

Advisory by default (exit 0). CI remains the merge authority.

Requires: `git`, `bash`, `python3`, `jq`, `npx` (jscpd). First Semgrep run may download packs.

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
