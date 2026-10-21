#!/usr/bin/env python3
"""IDE MCP: quality gate with live progress (no silent long wait)."""
from __future__ import annotations

import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Optional

from mcp.server.fastmcp import Context, FastMCP

mcp = FastMCP(
    "agentic-quality-gate",
    instructions=(
        "Sonar-replacement quality gate for the current workspace. "
        "Call run_quality_gate repeatedly until the reply starts with "
        "'# Quality gate'. Between calls, show the user the ## Live log "
        "lines so they see activity (like a build). Explain final findings "
        "with What / Why / How to fix. Coverage is CI-only."
    ),
)

JOB_TIMEOUT_SEC = 600
POLL_WAIT_SEC = 8
MAX_LOG_CHUNK = 40


def _hub_root() -> Path:
    env = (os.environ.get("AGENTIC_QUALITY_GATE_HOME") or "").strip()
    if env:
        return Path(env).expanduser().resolve()
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


def _job_key(workspace: Path, base: str, staged: bool, files: Optional[list[str]]) -> str:
    raw = json.dumps(
        {
            "workspace": str(workspace),
            "base": base,
            "staged": staged,
            "files": files or [],
        },
        sort_keys=True,
    )
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def _job_dir(key: str) -> Path:
    path = _cache_dir() / "jobs" / key
    path.mkdir(parents=True, exist_ok=True)
    return path


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _read_meta(job: Path) -> dict[str, Any]:
    meta_path = job / "meta.json"
    if not meta_path.is_file():
        return {}
    try:
        data = json.loads(meta_path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def _write_meta(job: Path, meta: dict[str, Any]) -> None:
    (job / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")


def _read_log_lines(job: Path) -> list[str]:
    log_path = job / "live.log"
    if not log_path.is_file():
        return []
    try:
        text = log_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    return text.splitlines()


def _load_result(tmp: Path, exit_code: int, log_tail: str) -> dict[str, Any]:
    gate_path = tmp / "gate-result.json"
    findings_path = tmp / "findings.json"
    if findings_path.is_file() or gate_path.is_file():
        gate: dict[str, Any] = {}
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
        return {
            "status": gate.get("status", "n/a"),
            "mode": gate.get("mode", "advisory"),
            "counts": gate.get("counts") or {},
            "fail_reasons": gate.get("fail_reasons") or [],
            "warn_reasons": gate.get("warn_reasons") or [],
            "findings": findings,
            "summary_md": md,
            "exit_code": exit_code,
            "stderr_tail": log_tail[-2000:],
        }
    return {
        "status": "fail",
        "error": "quality gate produced no JSON",
        "exit_code": exit_code,
        "stdout_tail": log_tail[-2000:],
        "stderr_tail": "",
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


def _format_progress(
    *,
    workspace: str,
    new_lines: list[str],
    cursor: int,
    total_lines: int,
    elapsed: float,
    job: Path,
) -> str:
    shown = new_lines[-MAX_LOG_CHUNK:]
    body = "\n".join(shown) if shown else "(starting engines — Semgrep / duplication / complexity…)"
    return "\n".join(
        [
            "## Quality gate progress — still running",
            f"Workspace: `{workspace}`",
            f"Elapsed: ~{int(elapsed)}s · log lines: {total_lines}",
            "",
            "Show the user this live log (like a build). Then **call "
            "`run_quality_gate` again with the same arguments** until the "
            "reply starts with `# Quality gate`.",
            "",
            f"log_cursor: {cursor}",
            f"live_log: `{job / 'live.log'}`",
            "",
            "## Live log",
            "```",
            body,
            "```",
        ]
    )


def _emit(ctx: Optional[Context], message: str, progress: float) -> None:
    if ctx is None:
        return
    try:
        ctx.info(message)
        ctx.report_progress(progress=progress, message=message[:120])
    except Exception:  # noqa: BLE001 — client may not support notifications
        pass


def _start_job(
    workspace: Path,
    *,
    base: str,
    staged: bool,
    files: Optional[list[str]],
) -> Path:
    hub = _hub_root()
    script = hub / "scripts" / "local-gate.sh"
    if not script.is_file():
        raise FileNotFoundError(f"missing {script}")

    key = _job_key(workspace, base, staged, files)
    job = _job_dir(key)
    tmp = _cache_dir() / "tmp"
    tmp.mkdir(parents=True, exist_ok=True)

    log_path = job / "live.log"
    log_path.write_text("", encoding="utf-8")

    gate_args = [str(script), "--base", base, "--json"]
    if staged:
        gate_args.append("--staged")
    if files:
        gate_args.append("--files")
        gate_args.extend(files)

    env = os.environ.copy()
    env["AGENTIC_TMP"] = str(tmp)
    env["PIPELINE_DIR"] = str(hub)
    env["AGENTIC_QUALITY_GATE_HOME"] = str(hub)
    env["HOME"] = env.get("HOME") or str(Path.home())
    env["PYTHONUNBUFFERED"] = "1"

    exit_path = job / "exit_code"
    if exit_path.exists():
        exit_path.unlink()

    # Small Python runner: line-friendly stdio + reliable exit_code file
    runner = job / "run_gate.py"
    runner.write_text(
        f"""#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
args = {json.dumps(gate_args)}
exit_file = Path({json.dumps(str(exit_path))})
env = os.environ.copy()
env["PYTHONUNBUFFERED"] = "1"
cmd = ["bash", *args]
# Prefer stdbuf for line-buffered scanner logs when available
from shutil import which
if which("stdbuf"):
    cmd = ["stdbuf", "-oL", "-eL", *cmd]
p = subprocess.run(cmd, cwd={json.dumps(str(workspace))}, env=env)
exit_file.write_text(str(p.returncode) + "\\n", encoding="utf-8")
sys.exit(p.returncode)
""",
        encoding="utf-8",
    )
    runner.chmod(0o755)

    log_fh = open(log_path, "a", encoding="utf-8")  # noqa: SIM115 — child inherits fd
    proc = subprocess.Popen(
        [sys.executable, str(runner)],
        cwd=str(workspace),
        env=env,
        stdout=log_fh,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    log_fh.close()

    meta = {
        "pid": proc.pid,
        "workspace": str(workspace),
        "base": base,
        "staged": staged,
        "files": files or [],
        "started_at": time.time(),
        "status": "running",
        "tmp": str(tmp),
        "log_cursor": 0,
    }
    _write_meta(job, meta)
    return job


def _read_exit_code(job: Path) -> Optional[int]:
    path = job / "exit_code"
    if not path.is_file():
        return None
    try:
        return int(path.read_text(encoding="utf-8").strip() or "0")
    except ValueError:
        return 0


def _finalize_if_done(job: Path, meta: dict[str, Any]) -> Optional[dict[str, Any]]:
    pid = int(meta.get("pid") or 0)
    exit_code = _read_exit_code(job)
    alive = _pid_alive(pid)

    if alive and exit_code is None:
        started = float(meta.get("started_at") or 0)
        if started and (time.time() - started) > JOB_TIMEOUT_SEC:
            try:
                os.killpg(pid, signal.SIGTERM)
            except OSError:
                try:
                    os.kill(pid, signal.SIGTERM)
                except OSError:
                    pass
            meta["status"] = "timeout"
            meta["exit_code"] = 124
            _write_meta(job, meta)
            tmp = Path(str(meta.get("tmp") or (_cache_dir() / "tmp")))
            log = "\n".join(_read_log_lines(job))
            return _load_result(tmp, 124, log + "\n(timeout after 10 minutes)")
        return None

    if exit_code is None:
        # Process gone but exit file not written yet — wait next poll
        if alive:
            return None
        exit_code = 0

    meta["status"] = "done"
    meta["exit_code"] = exit_code
    _write_meta(job, meta)
    tmp = Path(str(meta.get("tmp") or (_cache_dir() / "tmp")))
    log = "\n".join(_read_log_lines(job))
    return _load_result(tmp, exit_code, log)


def _poll_job(
    job: Path,
    *,
    workspace: str,
    ctx: Optional[Context],
) -> str:
    meta = _read_meta(job)
    if not meta:
        return "Error: no quality-gate job state. Call run_quality_gate again to start."

    cursor = int(meta.get("log_cursor") or 0)
    deadline = time.time() + POLL_WAIT_SEC
    new_lines: list[str] = []

    while time.time() < deadline:
        all_lines = _read_log_lines(job)
        if len(all_lines) > cursor:
            chunk = all_lines[cursor:]
            new_lines.extend(chunk)
            for line in chunk:
                _emit(ctx, line, float(cursor + 1))
                cursor += 1
            meta["log_cursor"] = cursor
            _write_meta(job, meta)

        result = _finalize_if_done(job, _read_meta(job))
        if result is not None:
            if result.get("status") == "fail" and "timeout" in str(result.get("stderr_tail") or ""):
                return "Error: quality gate timed out (10 minutes)."
            # Final report MUST start with "# Quality gate" (Agent stop signal)
            tail = new_lines[-15:] or all_lines[-15:]
            final = _format_for_agent(result, workspace)
            if tail:
                final = (
                    final
                    + "\n\n## Final live log\n```\n"
                    + "\n".join(tail)
                    + "\n```"
                )
            # Mark job consumed so next ask starts fresh
            meta = _read_meta(job)
            meta["status"] = "reported"
            _write_meta(job, meta)
            return final

        time.sleep(0.4)

    all_lines = _read_log_lines(job)
    if len(all_lines) > cursor:
        new_lines.extend(all_lines[cursor:])
        cursor = len(all_lines)
        meta["log_cursor"] = cursor
        _write_meta(job, meta)

    started = float(meta.get("started_at") or time.time())
    return _format_progress(
        workspace=workspace,
        new_lines=new_lines or all_lines[-MAX_LOG_CHUNK:],
        cursor=cursor,
        total_lines=len(all_lines),
        elapsed=time.time() - started,
        job=job,
    )


def _validate_workspace(workspace_path: str) -> Path | str:
    workspace = Path(workspace_path).expanduser().resolve()
    if not workspace.is_dir():
        return f"Error: workspace not found: {workspace}"
    if not (workspace / ".git").exists() and not (workspace / ".git").is_file():
        if not list(workspace.glob(".git")):
            return f"Error: not a git repo: {workspace}"
    return workspace


@mcp.tool()
def run_quality_gate(
    workspace_path: str,
    base: str = "main",
    staged: bool = False,
    files: Optional[list[str]] = None,
    ctx: Optional[Context] = None,
) -> str:
    """Run the quality gate with live progress (pre-PR).

    IMPORTANT for Agent UX:
    - First call starts the scan and returns ## Quality gate progress + live log.
    - Call this tool AGAIN with the same args until the reply starts with
      "# Quality gate" (final report).
    - After each progress reply, show the ## Live log to the user so they see
      activity (like npm install) — do not stay silent.

    Scans changed files vs base with Semgrep, duplication %, complexity.
    Coverage is CI-only.

    Args:
        workspace_path: Absolute path to the application git repo root.
        base: Git base branch/ref (default main).
        staged: If true, only staged files.
        files: Optional explicit file paths relative to workspace.
    """
    checked = _validate_workspace(workspace_path)
    if isinstance(checked, str):
        return checked
    workspace = checked
    base = base or "main"

    key = _job_key(workspace, base, bool(staged), files)
    job = _job_dir(key)
    meta = _read_meta(job)
    status = meta.get("status")
    pid = int(meta.get("pid") or 0)

    # Fresh start when idle / already reported / dead pid
    if status in (None, "", "reported", "done", "timeout", "error") or (
        status == "running" and not _pid_alive(pid)
    ):
        # If a stale "running" with dead pid, treat as new
        try:
            _emit(ctx, f"Starting quality gate on {workspace}…", 0)
            _start_job(workspace, base=base, staged=bool(staged), files=files)
        except Exception as exc:  # noqa: BLE001
            return f"Error starting quality gate: {exc}"
        # Small settle so first logs appear
        time.sleep(0.6)

    return _poll_job(job, workspace=str(workspace), ctx=ctx)


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
            "hint": (
                "Ask: Run the quality gate on my changes. "
                "Agent will call run_quality_gate repeatedly and show live logs."
            ),
        },
        indent=2,
    )


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
