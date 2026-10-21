#!/usr/bin/env python3
"""Cursor MCP: run the same PR quality gate locally (no admin, user cache)."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Optional

from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "agentic-quality-gate",
    instructions=(
        "Sonar-replacement quality gate for the current workspace. "
        "Use run_quality_gate before the user opens a PR. Explain findings "
        "with What / Why / How to fix. Coverage is CI-only."
    ),
)


def _hub_root() -> Path:
    """Hub checkout: env override, or parent of mcp/ package."""
    env = (os.environ.get("AGENTIC_QUALITY_GATE_HOME") or "").strip()
    if env:
        return Path(env).expanduser().resolve()
    # mcp/src/aqg_mcp/server.py → hub root is parents[3]
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "scripts" / "local-gate.sh").is_file():
            return parent
    raise RuntimeError(
        "Cannot find agentic-quality-gate hub. Set AGENTIC_QUALITY_GATE_HOME."
    )


def _cache_dir() -> Path:
    base = Path(
        os.environ.get("AGENTIC_QUALITY_GATE_CACHE")
        or (Path.home() / ".cache" / "agentic-quality-gate")
    ).expanduser()
    base.mkdir(parents=True, exist_ok=True)
    return base


def _run_local_gate(
    workspace: Path,
    *,
    base: str,
    staged: bool,
    files: Optional[list[str]],
) -> dict[str, Any]:
    hub = _hub_root()
    script = hub / "scripts" / "local-gate.sh"
    if not script.is_file():
        raise FileNotFoundError(f"missing {script}")

    cache = _cache_dir()
    tmp = cache / "tmp"
    tmp.mkdir(parents=True, exist_ok=True)

    cmd = ["bash", str(script), "--base", base, "--json"]
    if staged:
        cmd.append("--staged")
    if files:
        cmd.append("--files")
        cmd.extend(files)

    env = os.environ.copy()
    env["AGENTIC_TMP"] = str(tmp)
    env["PIPELINE_DIR"] = str(hub)
    env["AGENTIC_QUALITY_GATE_HOME"] = str(hub)
    # Keep Semgrep venv reusable across runs (install-semgrep uses AGENTIC_TMP)
    # local-gate clears AGENTIC_TMP — use a persistent prefix beside tmp
    env["HOME"] = env.get("HOME") or str(Path.home())

    proc = subprocess.run(
        cmd,
        cwd=str(workspace),
        env=env,
        capture_output=True,
        text=True,
        timeout=600,
    )
    # local-gate prints logs to stdout before JSON when --json; take last JSON object
    stdout = proc.stdout or ""
    payload: dict[str, Any] = {}
    # Prefer artifacts on disk
    gate_path = tmp / "gate-result.json"
    findings_path = tmp / "findings.json"
    if findings_path.is_file() or gate_path.is_file():
        gate = {}
        findings: list[Any] = []
        if gate_path.is_file():
            gate = json.loads(gate_path.read_text(encoding="utf-8"))
        if findings_path.is_file():
            bundle = json.loads(findings_path.read_text(encoding="utf-8"))
            findings = bundle.get("findings") if isinstance(bundle, dict) else bundle
            if not isinstance(findings, list):
                findings = []
        md = ""
        md_path = tmp / "quality-gate.md"
        if md_path.is_file():
            md = md_path.read_text(encoding="utf-8")
        payload = {
            "status": gate.get("status", "n/a"),
            "mode": gate.get("mode", "advisory"),
            "counts": gate.get("counts") or {},
            "fail_reasons": gate.get("fail_reasons") or [],
            "warn_reasons": gate.get("warn_reasons") or [],
            "findings": findings,
            "summary_md": md,
            "exit_code": proc.returncode,
            "stderr_tail": (proc.stderr or "")[-2000:],
        }
        return payload

    # Fallback: parse JSON from stdout
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    # Last resort: whole stdout as JSON
    try:
        start = stdout.rfind("{")
        if start >= 0:
            return json.loads(stdout[start:])
    except json.JSONDecodeError:
        pass
    return {
        "status": "fail",
        "error": "quality gate produced no JSON",
        "exit_code": proc.returncode,
        "stdout_tail": stdout[-2000:],
        "stderr_tail": (proc.stderr or "")[-2000:],
        "findings": [],
    }


def _format_for_agent(result: dict[str, Any], workspace: str) -> str:
    status = result.get("status", "n/a")
    lines = [
        f"# Quality gate — `{status}`",
        f"Workspace: `{workspace}`",
        "",
        result.get("summary_md") or "_No summary._",
        "",
        "## Findings (explain each with What / Why / How to fix)",
    ]
    findings = result.get("findings") or []
    if not findings:
        lines.append("_No findings._")
    for f in findings[:50]:
        if not isinstance(f, dict):
            continue
        loc = f.get("path") or "(summary)"
        if f.get("start_line"):
            loc = f"{loc}:{f['start_line']}"
        lines.append(
            f"- **{f.get('severity', 'info')}** `{f.get('rule_id')}` @ `{loc}` — "
            f"{(f.get('message') or '').strip()}"
        )
        rem = (f.get("remediation") or "").strip()
        if rem:
            lines.append(f"  - How to fix: {rem[:300]}")
    if len(findings) > 50:
        lines.append(f"_…and {len(findings) - 50} more._")
    err = result.get("error")
    if err:
        lines.extend(["", f"Error: {err}"])
        if result.get("stderr_tail"):
            lines.append("```")
            lines.append(str(result["stderr_tail"])[:1500])
            lines.append("```")
    lines.extend(
        [
            "",
            "Tell the user what to fix before opening the PR. "
            "CI PR Quality Gate remains the merge authority.",
        ]
    )
    return "\n".join(lines)


@mcp.tool()
def run_quality_gate(
    workspace_path: str,
    base: str = "main",
    staged: bool = False,
    files: Optional[list[str]] = None,
) -> str:
    """Run the Sonar-replacement quality gate on a workspace (pre-PR).

    Scans changed files vs base (or staged files) with Semgrep hotspots,
    duplication % on new code, and complexity — same engines as GitHub PR CI.
    Coverage is not run locally (CI-only).

    Args:
        workspace_path: Absolute path to the application git repo root.
        base: Git base branch/ref (default main).
        staged: If true, only staged files (pre-commit style).
        files: Optional explicit file paths relative to workspace.
    """
    workspace = Path(workspace_path).expanduser().resolve()
    if not workspace.is_dir():
        return f"Error: workspace not found: {workspace}"
    if not (workspace / ".git").exists() and not (workspace / ".git").is_file():
        # allow worktrees where .git is a file
        if not list(workspace.glob(".git")):
            return f"Error: not a git repo: {workspace}"

    try:
        result = _run_local_gate(
            workspace, base=base or "main", staged=bool(staged), files=files
        )
    except subprocess.TimeoutExpired:
        return "Error: quality gate timed out (10 minutes)."
    except Exception as exc:  # noqa: BLE001 — surface to Agent
        return f"Error running quality gate: {exc}"

    return _format_for_agent(result, str(workspace))


@mcp.tool()
def quality_gate_status() -> str:
    """Return hub path, cache path, and whether the local CLI is available."""
    try:
        hub = _hub_root()
    except Exception as exc:  # noqa: BLE001
        return json.dumps({"ok": False, "error": str(exc)})
    script = hub / "scripts" / "local-gate.sh"
    return json.dumps(
        {
            "ok": script.is_file(),
            "hub": str(hub),
            "local_gate": str(script),
            "cache": str(_cache_dir()),
            "hint": "Ask: Run the quality gate on my changes",
        },
        indent=2,
    )


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
