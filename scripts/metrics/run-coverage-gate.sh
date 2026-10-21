#!/usr/bin/env bash
# Derive coverage findings for PR-changed files from artifacts or workspace reports.
# Looks in AGENTIC_TMP (checks artifacts) and common coverage output paths.
set -euo pipefail
# shellcheck source=../common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/common.sh"
# shellcheck source=engine-health.sh
source "$(cd "$(dirname "$0")" && pwd)/engine-health.sh"

METRICS_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${AGENTIC_TMP}/coverage-findings.json"
CHANGED="${AGENTIC_TMP}/pr-changed-files.txt"
THRESHOLD="${COVERAGE_THRESHOLD_PCT:-80}"

mkdir -p "$AGENTIC_TMP"
echo '[]' > "$OUT"

agentic_log "┌─ coverage (changed files) ─┐"

set +e
python3 "${METRICS_DIR}/normalize-coverage.py" \
  "$CHANGED" \
  "$OUT" \
  "$THRESHOLD" \
  "$AGENTIC_TMP" \
  "$(pwd)"
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  write_tooling_finding "coverage" "normalize-coverage exited ${RC}" "$OUT"
  record_engine "coverage" "failed" "normalize-coverage exited ${RC}"
  exit 1
fi
record_engine "coverage" "ok" "coverage findings written"
exit 0
