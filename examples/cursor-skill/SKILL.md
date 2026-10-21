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

Use MCP tool `run_quality_gate` from server **agentic-quality-gate**:

- `workspace_path`: absolute path to the app repo root
- `base`: usually `main`
- `staged`: false (unless they only want staged files)

**Live progress (required):** The tool returns in short chunks so the user is not
left staring at a silent spinner.

1. Tell the user: “Starting the quality gate — I’ll stream the log while it runs.”
2. Call `run_quality_gate`.
3. If the reply starts with `## Quality gate progress`, **show the ## Live log
   to the user**, then call `run_quality_gate` again with the **same** arguments.
4. Repeat until the reply starts with `# Quality gate` (final report).

If MCP is missing, tell the user to run once:

```bash
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-ide.sh | bash
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
