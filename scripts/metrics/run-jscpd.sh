#!/usr/bin/env bash
# Detect copy-paste duplication (jscpd) on PR-changed paths / roots.
set -euo pipefail
# shellcheck source=../common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/common.sh"
# shellcheck source=engine-health.sh
source "$(cd "$(dirname "$0")" && pwd)/engine-health.sh"

METRICS_DIR="$(cd "$(dirname "$0")" && pwd)"
JSCPD_VERSION="${JSCPD_VERSION:-4.0.5}"
RAW="${AGENTIC_TMP}/jscpd-raw.json"
OUT="${AGENTIC_TMP}/jscpd-findings.json"
LANG_FILE="${AGENTIC_TMP}/metrics-languages.json"
CHANGED="${AGENTIC_TMP}/pr-changed-files.txt"

mkdir -p "$AGENTIC_TMP"
echo '[]' > "$OUT"

agentic_log "┌─ jscpd (duplication) ─┐"

CODE_COUNT=$(jq -r '.pr_code_file_count // 0' "$LANG_FILE" 2>/dev/null || echo 0)
if [[ "${CODE_COUNT}" -eq 0 ]]; then
  agentic_log "  No PR code files — skip jscpd"
  record_engine "jscpd" "skipped" "no PR code files"
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  agentic_log "  ✗ npx not available — failing jscpd (fail-closed)"
  write_tooling_finding "jscpd" "npx not available on runner" "$OUT"
  record_engine "jscpd" "failed" "npx not available"
  exit 1
fi

PATHS_FILE="${AGENTIC_TMP}/jscpd-paths.txt"
: > "$PATHS_FILE"
if [[ -f "$CHANGED" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" || ! -e "$f" ]] && continue
    echo "$f" >> "$PATHS_FILE"
  done < "$CHANGED"
fi
if [[ -s "$PATHS_FILE" ]]; then
  head -n 300 "$PATHS_FILE" > "${PATHS_FILE}.trim" && mv "${PATHS_FILE}.trim" "$PATHS_FILE"
fi

if [[ ! -s "$PATHS_FILE" ]]; then
  agentic_log "  No on-disk paths — skip jscpd"
  record_engine "jscpd" "skipped" "no on-disk paths"
  exit 0
fi

REPORT_DIR="${AGENTIC_TMP}/jscpd-report"
rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

set +e
npx --yes "jscpd@${JSCPD_VERSION}" \
  --silent \
  --reporters json \
  --output "$REPORT_DIR" \
  --min-lines 10 \
  --min-tokens 50 \
  --ignore "**/node_modules/**,**/vendor/**,**/.git/**,**/dist/**,**/build/**,**/.terraform/**,**/coverage/**" \
  -- $(tr '\n' ' ' < "$PATHS_FILE") \
  >"${AGENTIC_TMP}/jscpd-stdout.txt" 2>"${AGENTIC_TMP}/jscpd-stderr.txt"
RC=$?
set -e

if [[ -f "${REPORT_DIR}/jscpd-report.json" ]]; then
  cp "${REPORT_DIR}/jscpd-report.json" "$RAW"
elif [[ -f "jscpd-report.json" ]]; then
  mv jscpd-report.json "$RAW"
else
  agentic_log "  ✗ jscpd produced no JSON (exit ${RC}) — failing job"
  write_tooling_finding "jscpd" "produced no JSON report (exit ${RC})" "$OUT"
  record_engine "jscpd" "failed" "no JSON report (exit ${RC})"
  exit 1
fi

# Sonar-style density needs new-lines denominator (added lines on PR)
NEW_LINES=0
BASE_REF="${GITHUB_BASE_REF:-main}"
if [[ -n "${AGENTIC_FORCE_NEW_LINES:-}" ]]; then
  NEW_LINES="${AGENTIC_FORCE_NEW_LINES}"
elif git rev-parse --verify "origin/${BASE_REF}" >/dev/null 2>&1; then
  NEW_LINES=$(git diff --numstat "origin/${BASE_REF}...HEAD" 2>/dev/null \
    | awk '{ add+=$1 } END { print add+0 }' || echo 0)
fi
MAX_PCT="${JSCPD_MAX_PCT_NEW_CODE:-3}"

python3 "${METRICS_DIR}/normalize-jscpd.py" "$RAW" "$CHANGED" "$OUT" "$NEW_LINES" "$MAX_PCT"
record_engine "jscpd" "ok" "report written (new_lines=${NEW_LINES}, max_pct=${MAX_PCT})"
exit 0
