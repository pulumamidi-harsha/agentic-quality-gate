#!/usr/bin/env bash
# Thin entrypoint: language detect → configs → install → scan → normalize.
# Fail-closed: install/scan infra errors exit non-zero.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
METRICS_DIR="${SCRIPT_DIR}/metrics"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=metrics/engine-health.sh
source "${METRICS_DIR}/engine-health.sh"

agentic_log ""
agentic_log "┌─────────────────────────────────────────────────────┐"
agentic_log "│  Semgrep metrics (stack-aware · PR-scoped)            │"
agentic_log "└─────────────────────────────────────────────────────┘"

bash "${METRICS_DIR}/detect-languages.sh"
bash "${METRICS_DIR}/select-semgrep-configs.sh"

SCAN_MODE=$(jq -r '.scan_mode // "skip"' "${AGENTIC_TMP}/metrics-languages.json" 2>/dev/null || echo skip)
if [[ "$SCAN_MODE" == "skip" ]]; then
  echo '{"results":[]}' > "${AGENTIC_TMP}/semgrep-raw.json"
  echo '[]' > "${AGENTIC_TMP}/semgrep-findings.json"
  record_engine "semgrep" "skipped" "no scannable code in PR"
  write_github_output "semgrep_findings" "0"
  write_github_output "semgrep_in_diff" "0"
  exit 0
fi

set +e
bash "${METRICS_DIR}/install-semgrep.sh"
INSTALL_RC=$?
set -e
if [[ $INSTALL_RC -ne 0 ]]; then
  write_tooling_finding "semgrep" "install failed (exit ${INSTALL_RC})" \
    "${AGENTIC_TMP}/semgrep-findings.json"
  record_engine "semgrep" "failed" "install failed (exit ${INSTALL_RC})"
  exit 1
fi

bash "${METRICS_DIR}/scan-semgrep.sh"

# Keep tooling findings from fail-closed paths; otherwise normalize raw → findings.
if [[ -f "${AGENTIC_TMP}/semgrep-findings.json" ]] \
  && jq -e '.[0].rule_id == "engine_unavailable"' "${AGENTIC_TMP}/semgrep-findings.json" >/dev/null 2>&1; then
  agentic_log "  Keeping tooling finding (scanner failed)"
else
  python3 "${METRICS_DIR}/normalize-semgrep.py" \
    "${AGENTIC_TMP}/semgrep-raw.json" \
    "${AGENTIC_TMP}/pr-changed-files.txt" \
    "${AGENTIC_TMP}/semgrep-findings.json"
fi

COUNT=$(jq 'length' "${AGENTIC_TMP}/semgrep-findings.json" 2>/dev/null || echo 0)
IN_DIFF=$(jq '[.[] | select(.in_pr_diff == true)] | length' "${AGENTIC_TMP}/semgrep-findings.json" 2>/dev/null || echo 0)
write_github_output "semgrep_findings" "$COUNT"
write_github_output "semgrep_in_diff" "$IN_DIFF"
exit 0
