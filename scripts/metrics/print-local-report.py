#!/usr/bin/env python3
"""Print a terminal report for local / IDE quality-gate runs."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load_json(path: Path, default: Any) -> Any:
    if not path.is_file():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tmp", required=True, help="AGENTIC_TMP directory")
    ap.add_argument("--json", action="store_true", help="Emit machine-readable JSON only")
    args = ap.parse_args()
    tmp = Path(args.tmp)

    gate = load_json(tmp / "gate-result.json", {})
    bundle = load_json(tmp / "findings.json", {})
    findings = bundle.get("findings") if isinstance(bundle, dict) else bundle
    if not isinstance(findings, list):
        findings = []
    engines = load_json(tmp / "engine-status.json", {})
    md = (tmp / "quality-gate.md").read_text(encoding="utf-8") if (tmp / "quality-gate.md").is_file() else ""

    payload = {
        "status": gate.get("status", "n/a"),
        "mode": gate.get("mode", "advisory"),
        "blocking": gate.get("blocking", False),
        "counts": gate.get("counts") or {},
        "fail_reasons": gate.get("fail_reasons") or [],
        "warn_reasons": gate.get("warn_reasons") or [],
        "engines": engines.get("engines") or {},
        "findings": findings,
        "summary_md": md,
    }

    if args.json:
        print(json.dumps(payload, indent=2))
        return 0

    status = payload["status"]
    emoji = {"pass": "✅", "warn": "⚠️", "fail": "❌"}.get(status, "ℹ️")
    print("")
    print(f"{emoji} Local Quality Gate — {status}")
    print(f"Status: {status} · Mode: {payload['mode']} · Blocking: {'yes' if payload['blocking'] else 'no'}")
    print("")

    if md.strip():
        # Strip markdown noise for terminal
        for line in md.splitlines():
            if line.startswith("#"):
                print(line.lstrip("# ").strip())
            elif line.startswith("- "):
                print(line)
            elif line.startswith("**Status:**") or line.startswith("####"):
                print(line.replace("**", "").replace("#### ", "").replace("`", ""))
            elif line.strip():
                print(line.replace("**", "").replace("`", ""))
        print("")

    lineable = [
        f
        for f in findings
        if f.get("path") and f.get("start_line") and f.get("category") != "tooling"
    ]
    if lineable:
        print(f"Findings with locations ({len(lineable)}):")
        for f in sorted(
            lineable,
            key=lambda x: (x.get("severity") != "error", str(x.get("path")), int(x.get("start_line") or 0)),
        )[:40]:
            sev = (f.get("severity") or "info")[0].upper()
            loc = f"{f.get('path')}:{f.get('start_line')}"
            msg = (f.get("message") or "").replace("\n", " ")[:100]
            print(f"  [{sev}] {loc} — {msg}")
        if len(lineable) > 40:
            print(f"  … and {len(lineable) - 40} more")
        print("")

    failed_eng = engines.get("failed_engines") or []
    if failed_eng:
        print("Scanner failures:")
        for name in failed_eng:
            reason = ((engines.get("engines") or {}).get(name) or {}).get("reason")
            print(f"  ✗ {name}: {reason or 'failed'}")
        print("")

    print("Tip: fix locally, then open the PR. CI remains the merge authority.")
    print(f"Artifacts: {tmp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
