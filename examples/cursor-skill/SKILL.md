---
name: quality-gate
description: >-
  Run agentic-quality-gate (Sonar-replacement) on local changes. Trigger on
  run-qg, /run-qg, "run qg", quality gate, pre-PR scan, Semgrep, hotspots,
  duplication, complexity, or Sonar-like checks in the IDE.
---

# Quality gate (pre-PR)

## When to use

- User types **`run-qg`** (preferred short form) or `/run-qg` or “run qg”
- User asks for quality gate / Sonar / pre-PR / hotspots / duplication / complexity
- User is about to open a pull request

## How to run

Use MCP tool `run_quality_gate` from server **agentic-quality-gate**:

- `workspace_path`: absolute path to the app repo root
- `base`: usually `main`
- `staged`: false (unless they only want staged files)

**Live progress (required):** The tool returns in short chunks so the user is not
left staring at a silent spinner.

1. Tell the user: “Starting the quality gate (`run-qg`) — streaming the log…”
2. Call `run_quality_gate`.
3. If the reply starts with `## Quality gate progress`, **show the ## Live log
   to the user**, then call `run_quality_gate` again with the **same** arguments.
4. Repeat until the reply starts with `# Quality gate` (final report).

If MCP is missing, tell the user to run once from the app repo:

```bash
cd <app-root> && curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash && export PATH="$HOME/.local/bin:$PATH" && hash -r
```

then restart the IDE — do not fall back to other install paths.

## How to respond

- While running: paste each ## Live log chunk (like a build log). Do not stay silent.
- When finished: summarize Failed conditions first (status, hotspots, duplication %, complexity).
- For each important finding: **What** / **Why** / **How to fix** (use remediation).
- Do not dump huge tables.
- Remind: GitHub **PR Quality Gate** remains the merge authority; this is early feedback.

## Out of scope here

- Coverage (CI-only until lcov is wired)
- AI PR review (`agentic-review` hub)
- DAST / Burp
