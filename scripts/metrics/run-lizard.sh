#!/usr/bin/env bash
# Cyclomatic complexity via Lizard on PR-changed code files.
set -euo pipefail
# shellcheck source=../common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/common.sh"
# shellcheck source=engine-health.sh
source "$(cd "$(dirname "$0")" && pwd)/engine-health.sh"

METRICS_DIR="$(cd "$(dirname "$0")" && pwd)"
LIZARD_VERSION="${LIZARD_VERSION:-1.17.10}"
RAW="${AGENTIC_TMP}/lizard-raw.csv"
OUT="${AGENTIC_TMP}/lizard-findings.json"
LANG_FILE="${AGENTIC_TMP}/metrics-languages.json"
CHANGED="${AGENTIC_TMP}/pr-changed-files.txt"
THRESHOLD="${LIZARD_COMPLEXITY_THRESHOLD:-15}"

mkdir -p "$AGENTIC_TMP"
echo '[]' > "$OUT"

agentic_log "┌─ lizard (complexity) ─┐"

CODE_COUNT=$(jq -r '.pr_code_file_count // 0' "$LANG_FILE" 2>/dev/null || echo 0)
if [[ "${CODE_COUNT}" -eq 0 ]]; then
  agentic_log "  No PR code files — skip lizard"
  record_engine "lizard" "skipped" "no PR code files"
  exit 0
fi

USER_BIN="$(python3 -c 'import site; print(site.USER_BASE + "/bin")' 2>/dev/null || true)"
[[ -n "$USER_BIN" && -d "$USER_BIN" ]] && export PATH="${USER_BIN}:${PATH}"

if ! command -v lizard >/dev/null 2>&1; then
  agentic_log "  Installing lizard==${LIZARD_VERSION}"
  set +e
  python3 -m pip install --quiet "lizard==${LIZARD_VERSION}" \
    || pip3 install --quiet "lizard==${LIZARD_VERSION}"
  PIP_RC=$?
  set -e
  [[ -n "$USER_BIN" && -d "$USER_BIN" ]] && export PATH="${USER_BIN}:${PATH}"
  if [[ $PIP_RC -ne 0 ]] && ! command -v lizard >/dev/null 2>&1; then
    write_tooling_finding "lizard" "install failed (pip exit ${PIP_RC})" "$OUT"
    record_engine "lizard" "failed" "install failed"
    exit 1
  fi
fi

if command -v lizard >/dev/null 2>&1; then
  LIZARD=(lizard)
elif python3 -m lizard --help >/dev/null 2>&1; then
  LIZARD=(python3 -m lizard)
else
  write_tooling_finding "lizard" "CLI unavailable after install" "$OUT"
  record_engine "lizard" "failed" "CLI unavailable after install"
  exit 1
fi

TARGETS_FILE="${AGENTIC_TMP}/lizard-targets.txt"
: > "$TARGETS_FILE"
while IFS= read -r f; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  echo "$f" >> "$TARGETS_FILE"
done < <(jq -r '.pr_code_files[]?' "$LANG_FILE" 2>/dev/null || true)

if [[ ! -s "$TARGETS_FILE" ]]; then
  agentic_log "  No on-disk targets — skip lizard"
  record_engine "lizard" "skipped" "no on-disk targets"
  exit 0
fi
head -n 400 "$TARGETS_FILE" > "${TARGETS_FILE}.trim" && mv "${TARGETS_FILE}.trim" "$TARGETS_FILE"

set +e
"${LIZARD[@]}" -C 0 --csv $(tr '\n' ' ' < "$TARGETS_FILE") > "$RAW" 2>"${AGENTIC_TMP}/lizard-stderr.txt"
RC=$?
set -e

# Empty CSV with success can mean "no functions over threshold path" — still ok if RC=0
# and file exists. Hard-fail when the tool crashed.
if [[ $RC -ne 0 && ! -s "$RAW" ]]; then
  agentic_log "  ✗ lizard failed (exit ${RC}) with no output"
  write_tooling_finding "lizard" "scan failed (exit ${RC}) with no output" "$OUT"
  record_engine "lizard" "failed" "scan failed (exit ${RC})"
  exit 1
fi
if [[ ! -s "$RAW" ]]; then
  # Successful run with no rows — treat as ok empty
  echo '[]' > "$OUT"
  record_engine "lizard" "ok" "no functions reported"
  exit 0
fi

python3 "${METRICS_DIR}/normalize-lizard.py" "$RAW" "$CHANGED" "$OUT" "$THRESHOLD"
record_engine "lizard" "ok" "normalized"
exit 0
