#!/usr/bin/env bash
# Fail-closed helpers: record engine ok/skipped/failed + tooling findings.
# shellcheck shell=bash

record_engine() {
  local engine="$1"
  local status="$2" # ok | skipped | failed
  local reason="${3:-}"
  local status_file="${AGENTIC_TMP}/engine-status.json"
  mkdir -p "$AGENTIC_TMP"
  python3 - "$status_file" "$engine" "$status" "$reason" <<'PY'
import json, sys
from pathlib import Path

path, engine, status, reason = sys.argv[1:5]
p = Path(path)
data = {"engines": {}}
if p.is_file():
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        data = {"engines": {}}
if not isinstance(data.get("engines"), dict):
    data["engines"] = {}
data["engines"][engine] = {
    "status": status,
    "reason": reason or None,
}
failed = [k for k, v in data["engines"].items() if (v or {}).get("status") == "failed"]
data["ok"] = len(failed) == 0
data["failed_engines"] = failed
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"  Engine {engine}: {status}" + (f" — {reason}" if reason else ""))
PY
}

write_tooling_finding() {
  local engine="$1"
  local reason="$2"
  local out="$3"
  mkdir -p "$(dirname "$out")"
  python3 - "$engine" "$reason" "$out" <<'PY'
import json, sys
from pathlib import Path

engine, reason, out = sys.argv[1:4]
finding = {
    "engine": engine,
    "rule_id": "engine_unavailable",
    "severity": "error",
    "category": "tooling",
    "path": None,
    "start_line": None,
    "end_line": None,
    "message": f"{engine} failed to run: {reason}",
    "remediation": (
        "Open the workflow logs for this engine, fix the install/scan error, "
        "and re-run the PR check. Empty scanner output must not be treated as a clean PR."
    ),
    "in_pr_diff": True,
    "fingerprint": f"tooling:{engine}:unavailable",
    "raw": {"reason": reason},
}
Path(out).write_text(json.dumps([finding], indent=2) + "\n", encoding="utf-8")
PY
}

engines_failed() {
  local status_file="${AGENTIC_TMP}/engine-status.json"
  [[ -f "$status_file" ]] || return 1
  jq -e '.ok == false' "$status_file" >/dev/null 2>&1
}
