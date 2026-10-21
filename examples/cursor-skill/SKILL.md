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

1. Prefer the MCP tool `run_quality_gate` from server **agentic-quality-gate**:
   - `workspace_path`: absolute path to the app repo root
   - `base`: usually `main`
   - `staged`: false (unless they only want staged files)
2. If MCP is unavailable, run:

   ```bash
   bash "$HOME/.cursor/agentic-quality-gate/scripts/local-gate.sh" --json
   ```

   from the app repo (still user-space; no admin).

## How to respond

- Summarize Failed conditions first (status, hotspots, duplication %, complexity).
- For each important finding: **What** / **Why** / **How to fix** (use remediation).
- Do not dump huge tables.
- Remind: GitHub **PR Quality Gate** remains the merge authority; this is early feedback.

## Out of scope here

- Coverage (CI-only until lcov is wired)
- AI PR review (`agentic-review` hub)
- DAST / Burp
