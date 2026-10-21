# Adopt local / IDE quality gate (app repos)

Use this in application repos (e.g. `dso-os-frontend`) so developers see
Sonar-replacement findings **before** opening a PR.

CI (`PR Quality Gate` workflow) remains the merge authority.

## Prerequisites

- `git`, `bash`, `python3`, `jq`, `node`/`npx` (jscpd), network for first Semgrep install
- Clone or pin [`agentic-quality-gate`](https://github.com/pulumamidi-harsha/agentic-quality-gate)

## Option A — Cursor / VS Code task

1. Clone the hub next to the app (or set `AGENTIC_QUALITY_GATE_HOME`):

   ```bash
   export AGENTIC_QUALITY_GATE_HOME=/path/to/agentic-quality-gate
   ```

2. Copy [`vscode-tasks.json`](vscode-tasks.json) into the app’s `.vscode/tasks.json`
   (merge with existing tasks if needed).

3. In Cursor: **Terminal → Run Task… → “PR Quality Gate (local)”**

4. Or run from the app root:

   ```bash
   bash "$AGENTIC_QUALITY_GATE_HOME/scripts/local-gate.sh"
   bash "$AGENTIC_QUALITY_GATE_HOME/scripts/local-gate.sh" --strict
   ```

## Option B — pre-commit hook

1. Copy hooks from [`pre-commit-config.yaml`](pre-commit-config.yaml) into the app’s
   `.pre-commit-config.yaml` and **pin `rev` to a full SHA**.

2. Install:

   ```bash
   pip install pre-commit
   pre-commit install
   ```

3. On each commit, staged files are scanned (advisory). To block commits:

   ```yaml
   args: [--staged, --strict]
   ```

## Option C — one-off CLI (no IDE config)

```bash
cd /path/to/dso-os-frontend
bash /path/to/agentic-quality-gate/scripts/local-gate.sh --base main
```

Add `.agentic-quality-gate/` to the app `.gitignore` (local artifacts).

## What is checked locally

| Engine   | Local | Notes                          |
|----------|-------|--------------------------------|
| Semgrep  | yes   | Same package rules as CI       |
| jscpd %  | yes   | Duplication on new code ≤ 3%   |
| Lizard   | yes   | Complexity                     |
| Coverage | no    | CI-only (needs lcov from tests)|

## Pilot checklist (`dso-os-frontend`)

- [ ] Set `AGENTIC_QUALITY_GATE_HOME` or sibling clone
- [ ] Add VS Code/Cursor task (optional)
- [ ] Add pre-commit hook pinned to hub SHA (optional)
- [ ] Ignore `.agentic-quality-gate/`
- [ ] Keep `.github/workflows/quality-gate.yml` for PR CI
