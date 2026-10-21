#!/usr/bin/env bash
# Metrics orchestrator: load quality-gate package → run enabled engines → gate.
#
# Fail-closed: if an enabled engine fails to install/run (no usable output),
# the job exits non-zero even in advisory mode so users see a red check.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=metrics/engine-health.sh
source "${SCRIPT_DIR}/metrics/engine-health.sh"

PIPELINE_DIR="${PIPELINE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
PKG_JSON="${AGENTIC_TMP}/quality-package.json"

agentic_log ""
agentic_log "═══ Quality gate package (PR-scoped · multi-stack) ═══"

mkdir -p "$AGENTIC_TMP"
echo '{"engines":{},"ok":true,"failed_engines":[]}' > "${AGENTIC_TMP}/engine-status.json"

bash "${SCRIPT_DIR}/filter-pr-diff.sh"

python3 "${SCRIPT_DIR}/metrics/load-package.py" \
  "${PIPELINE_DIR}/config/quality-gate.yml" \
  "${PIPELINE_DIR}/config/packages" \
  "${PKG_JSON}"

SEMGREP_ON=$(jq -r '.semgrep_enabled // true' "$PKG_JSON")
DUP_ON=$(jq -r '.duplication // true' "$PKG_JSON")
COMPLEX_ON=$(jq -r '.complexity // true' "$PKG_JSON")
COV_ON=$(jq -r '.coverage // true' "$PKG_JSON")

if [[ "$COMPLEX_ON" == "true" ]]; then
  export LIZARD_COMPLEXITY_THRESHOLD
  LIZARD_COMPLEXITY_THRESHOLD=$(jq -r '.complexity_threshold // 15' "$PKG_JSON")
fi
if [[ "$COV_ON" == "true" ]]; then
  export COVERAGE_THRESHOLD_PCT
  COVERAGE_THRESHOLD_PCT=$(jq -r '.coverage_threshold // 80' "$PKG_JSON")
fi
if [[ "$DUP_ON" == "true" ]]; then
  export JSCPD_MAX_PCT_NEW_CODE
  JSCPD_MAX_PCT_NEW_CODE=$(jq -r '.duplication_max_pct // 3' "$PKG_JSON")
fi

run_engine() {
  local name="$1"
  shift
  agentic_log ""
  agentic_log "→ Running engine: ${name}"
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    agentic_log "✗ Engine ${name} failed (exit ${rc})"
    # Ensure a tooling finding exists if the script crashed before writing one
    local findings="${AGENTIC_TMP}/${name}-findings.json"
    if [[ "$name" == "semgrep" ]]; then
      findings="${AGENTIC_TMP}/semgrep-findings.json"
    elif [[ "$name" == "jscpd" ]]; then
      findings="${AGENTIC_TMP}/jscpd-findings.json"
    elif [[ "$name" == "lizard" ]]; then
      findings="${AGENTIC_TMP}/lizard-findings.json"
    elif [[ "$name" == "coverage" ]]; then
      findings="${AGENTIC_TMP}/coverage-findings.json"
    fi
    if [[ ! -f "$findings" ]] || ! jq -e 'length > 0' "$findings" >/dev/null 2>&1; then
      write_tooling_finding "$name" "engine exited ${rc}" "$findings"
    fi
    if ! jq -e --arg e "$name" '.engines[$e].status == "failed"' \
      "${AGENTIC_TMP}/engine-status.json" >/dev/null 2>&1; then
      record_engine "$name" "failed" "engine exited ${rc}"
    fi
    return "$rc"
  fi
  return 0
}

ENGINE_FAIL=0

if [[ "$SEMGREP_ON" == "true" ]]; then
  run_engine semgrep bash "${SCRIPT_DIR}/run-semgrep.sh" || ENGINE_FAIL=1
else
  mkdir -p "$AGENTIC_TMP"
  echo '[]' > "${AGENTIC_TMP}/semgrep-findings.json"
  bash "${SCRIPT_DIR}/metrics/detect-languages.sh"
  record_engine "semgrep" "skipped" "disabled in package"
fi

if [[ "$DUP_ON" == "true" ]]; then
  run_engine jscpd bash "${SCRIPT_DIR}/run-jscpd.sh" || ENGINE_FAIL=1
else
  echo '[]' > "${AGENTIC_TMP}/jscpd-findings.json"
  record_engine "jscpd" "skipped" "disabled in package"
fi

if [[ "$COMPLEX_ON" == "true" ]]; then
  run_engine lizard bash "${SCRIPT_DIR}/run-lizard.sh" || ENGINE_FAIL=1
else
  echo '[]' > "${AGENTIC_TMP}/lizard-findings.json"
  record_engine "lizard" "skipped" "disabled in package"
fi

if [[ "$COV_ON" == "true" ]]; then
  # Coverage missing report is a policy warn, not an infra failure
  run_engine coverage bash "${SCRIPT_DIR}/run-coverage-gate.sh" || ENGINE_FAIL=1
else
  echo '[]' > "${AGENTIC_TMP}/coverage-findings.json"
  record_engine "coverage" "skipped" "disabled in package"
fi

set +e
bash "${SCRIPT_DIR}/apply-quality-gate.sh"
GATE_RC=$?
set -e

# Surface engine failures in the compact summary even when advisory
if engines_failed || [[ "$ENGINE_FAIL" -ne 0 ]]; then
  python3 - "${AGENTIC_TMP}/engine-status.json" "${AGENTIC_TMP}/quality-gate.md" \
    "${AGENTIC_TMP}/gate-result.json" <<'PY'
import json, sys
from pathlib import Path

status_path, md_path, gate_path = sys.argv[1:4]
status = json.loads(Path(status_path).read_text(encoding="utf-8"))
failed = status.get("failed_engines") or []
reasons = []
for name in failed:
    eng = (status.get("engines") or {}).get(name) or {}
    reasons.append(f"- ❌ **Scanner {name} failed to run** — {eng.get('reason') or 'unknown error'}")

md = Path(md_path)
body = md.read_text(encoding="utf-8") if md.is_file() else ""
block = "#### Scanner failures (fail-closed)\n\n" + "\n".join(reasons) + "\n\n"
if "#### Scanner failures" not in body:
    if "#### Failed conditions" in body:
        body = body.replace("#### Failed conditions", block + "#### Failed conditions", 1)
    else:
        body = block + body
    md.write_text(body, encoding="utf-8")

if gate_path and Path(gate_path).is_file():
    gate = json.loads(Path(gate_path).read_text(encoding="utf-8"))
    gate["status"] = "fail"
    gate["blocking"] = True
    gate["exit_code"] = 1
    gate.setdefault("fail_reasons", [])
    for name in failed:
        msg = f"scanner {name} failed to run"
        if msg not in gate["fail_reasons"]:
            gate["fail_reasons"].append(msg)
    counts = gate.setdefault("counts", {})
    counts["scanner_failures"] = len(failed)
    Path(gate_path).write_text(json.dumps(gate, indent=2) + "\n", encoding="utf-8")
PY
  write_github_output "gate_status" "fail"
  write_github_output "gate_blocking" "true"
  agentic_log "═══ FAIL-CLOSED: one or more scanners did not run ═══"
  cat "${AGENTIC_TMP}/engine-status.json" || true
  exit 1
fi

agentic_log "═══ Done: findings.json · gate-result.json · quality-gate.md ═══"
cat "${AGENTIC_TMP}/engine-status.json" || true
exit "$GATE_RC"
