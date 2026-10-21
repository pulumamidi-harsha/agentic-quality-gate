---
name: quality-gate
description: >-
  Run the agentic-quality-gate Sonar-replacement checks on local changes before
  opening a PR. Use when the user asks to check quality, scan for hotspots,
  pre-PR review, Semgrep, duplication, complexity, or Sonar-like issues in the IDE.
---

# Quality gate (pre-PR)

## When to use

- User asks to run quality gate / Sonar checks / pre-PR scan
- User is about to open a pull request
- User wants security hotspots, duplication, or complexity on current changes

## How to run

Use the MCP tool `run_quality_gate` from server **agentic-quality-gate**:

- `workspace_path`: absolute path to the app repo root
- `base`: usually `main`
- `staged`: false (unless they only want staged files)

If MCP is missing, tell the user to run once:

```bash
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-ide.sh | bash
```

then restart the IDE — do not fall back to other install paths.

## How to respond

- Summarize Failed conditions first (status, hotspots, duplication %, complexity).
- For each important finding: **What** / **Why** / **How to fix** (use remediation).
- Do not dump huge tables.
- Remind: GitHub **PR Quality Gate** remains the merge authority; this is early feedback.

## Out of scope here

- Coverage (CI-only until lcov is wired)
- AI PR review (`agentic-review` hub)
- DAST / Burp
