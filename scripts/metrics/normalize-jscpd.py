#!/usr/bin/env python3
"""Normalize jscpd JSON into finding.schema.json rows (duplication).

Emits:
  - One finding per duplicated block (line comments)
  - One Sonar-style density finding: % duplicated lines on new code
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Optional, Set, Tuple


def strip_repo_rel(path: str) -> str:
    p = (path or "").strip().replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p


def _start_line(node: dict) -> Optional[int]:
    start = node.get("start") or node.get("startLoc") or 0
    if isinstance(start, dict):
        line = start.get("line") or start.get("startLine")
        return int(line) if line else None
    try:
        return int(start) if start else None
    except (TypeError, ValueError):
        return None


def main() -> int:
    if len(sys.argv) not in {4, 5, 6}:
        print(
            "usage: normalize-jscpd.py <jscpd-raw.json> <pr-changed-files.txt> "
            "<out.json> [new_lines] [max_pct]",
            file=sys.stderr,
        )
        return 2
    raw_path, changed_path, out_path = sys.argv[1:4]
    new_lines = int(sys.argv[4]) if len(sys.argv) >= 5 and sys.argv[4] else 0
    max_pct = float(sys.argv[5]) if len(sys.argv) >= 6 and sys.argv[5] else float(
        os.environ.get("JSCPD_MAX_PCT_NEW_CODE") or "3"
    )

    changed = set()
    if Path(changed_path).is_file():
        changed = {
            strip_repo_rel(ln)
            for ln in Path(changed_path).read_text(encoding="utf-8").splitlines()
            if ln.strip()
        }

    try:
        raw: Any = json.loads(Path(raw_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        Path(out_path).write_text("[]\n", encoding="utf-8")
        return 0

    duplicates = []
    if isinstance(raw, dict):
        duplicates = raw.get("duplicates") or raw.get("duplications") or []
    elif isinstance(raw, list):
        duplicates = raw

    findings: list[dict[str, Any]] = []
    # Sonar-style: unique (path, line) pairs on new/changed code that are duplicated
    dup_line_set: Set[Tuple[str, int]] = set()

    for dup in duplicates:
        if not isinstance(dup, dict):
            continue
        first = dup.get("firstFile") or dup.get("fragment") or {}
        second = dup.get("secondFile") or {}
        if not isinstance(first, dict):
            first = {}
        if not isinstance(second, dict):
            second = {}
        path = strip_repo_rel(first.get("name") or first.get("path") or "")
        other = strip_repo_rel(second.get("name") or second.get("path") or "")
        start_line = _start_line(first)
        other_start = _start_line(second)
        lines_count = int(dup.get("lines") or dup.get("lineCount") or 0)
        tokens = dup.get("tokens") or 0
        in_diff = (path in changed) or (other in changed)
        if not in_diff:
            continue

        for side_path, side_start in ((path, start_line), (other, other_start)):
            if not side_path or side_path not in changed or not side_start or lines_count <= 0:
                continue
            for offset in range(lines_count):
                dup_line_set.add((side_path, int(side_start) + offset))

        findings.append(
            {
                "engine": "jscpd",
                "rule_id": "duplication",
                "severity": "warning",
                "category": "duplication",
                "path": path or other or None,
                "start_line": start_line,
                "end_line": (int(start_line) + int(lines_count) - 1)
                if start_line and lines_count
                else None,
                "message": (
                    f"Duplicated block ({lines_count} lines"
                    f"{f', {tokens} tokens' if tokens else ''})"
                    + (f" also in `{other}`" if other and other != path else "")
                    + "."
                ),
                "remediation": (
                    "Extract the shared logic into one helper and call it from "
                    "both places (or delete the copy). Keep a single source of "
                    "truth so future fixes land once."
                    + (f" Duplicate also appears in `{other}`." if other and other != path else "")
                ),
                "in_pr_diff": True,
                "fingerprint": f"jscpd:{path}:{start_line}:{other}:{lines_count}",
                "raw": {
                    "lines": lines_count,
                    "other_path": other or None,
                    "tokens": tokens,
                },
            }
        )

    duplicated_lines = len(dup_line_set)
    # Prefer git new_lines; fall back to unique changed-file lines touched by dups
    denom = new_lines if new_lines > 0 else max(duplicated_lines, 1)
    pct = round(100.0 * duplicated_lines / denom, 1) if denom else 0.0

    if duplicated_lines > 0 and new_lines > 0:
        over = pct > max_pct
        findings.append(
            {
                "engine": "jscpd",
                "rule_id": "duplication_density",
                "severity": "warning" if over else "info",
                "category": "duplication",
                "path": None,
                "start_line": None,
                "end_line": None,
                "message": (
                    f"Duplication on new code is {pct}% "
                    f"({duplicated_lines} duplicated lines / {new_lines} new lines; "
                    f"required ≤ {max_pct:g}%)."
                ),
                "remediation": (
                    "Reduce copy-paste on new code (Sonar-style density). Extract "
                    "shared helpers so duplicated lines on new code stay ≤ "
                    f"{max_pct:g}%."
                ),
                "in_pr_diff": True,
                "fingerprint": f"jscpd:density:{pct}:{duplicated_lines}:{new_lines}",
                "raw": {
                    "duplication_pct": pct,
                    "duplicated_lines": duplicated_lines,
                    "new_lines": new_lines,
                    "threshold_pct": max_pct,
                    "over_threshold": over,
                },
            }
        )

    Path(out_path).write_text(json.dumps(findings, indent=2) + "\n", encoding="utf-8")
    blocks = sum(1 for f in findings if f.get("rule_id") == "duplication")
    print(
        f"  Normalized jscpd: {blocks} block(s), "
        f"density={pct}% ({duplicated_lines}/{new_lines or 'n/a'} new lines, "
        f"max {max_pct:g}%)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
