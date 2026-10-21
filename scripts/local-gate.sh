#!/usr/bin/env bash
# Local / IDE quality gate — same engines as CI, run before opening a PR.
#
# Usage (from an application repo):
#   /path/to/agentic-quality-gate/scripts/local-gate.sh
#   /path/to/agentic-quality-gate/scripts/local-gate.sh --staged
#   /path/to/agentic-quality-gate/scripts/local-gate.sh --base main --strict
#   /path/to/agentic-quality-gate/scripts/local-gate.sh --files src/a.ts src/b.py
#   /path/to/agentic-quality-gate/scripts/local-gate.sh --json
#
# Advisory by default (exit 0). Use --strict to exit 1 on gate fail / scanner fail.
# Coverage is skipped locally (CI-only). No GitHub API calls.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=metrics/engine-health.sh
source "${SCRIPT_DIR}/metrics/engine-health.sh"

STRICT=false
STAGED=false
JSON_OUT=false
BASE_REF="${GITHUB_BASE_REF:-main}"
FILES=()

usage() {
  cat <<'EOF'
agentic-quality-gate — local / IDE pre-PR checks

Usage:
  local-gate.sh [--base <ref>] [--staged] [--files <path>...] [--strict] [--json] [--help]

Options:
  --base <ref>   Diff base (default: main). Uses origin/<ref> when available.
  --staged       Only staged files (for pre-commit).
  --files ...    Explicit file list (skips git diff discovery).
  --strict       Exit 1 when gate status is warn/fail or a scanner fails.
  --json         Machine-readable JSON report on stdout.
  --help         Show this help.

Run from the application repository root (or any subdirectory of a git work tree).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=true; shift ;;
    --staged) STAGED=true; shift ;;
    --json) JSON_OUT=true; shift ;;
    --base)
      BASE_REF="${2:-}"
      [[ -n "$BASE_REF" ]] || { echo "error: --base requires a value" >&2; exit 2; }
      shift 2
      ;;
    --files)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        FILES+=("$1")
        shift
      done
      ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Resolve consumer git root
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "error: not inside a git repository — cd to your app repo first" >&2
  exit 2
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

export PIPELINE_DIR
export GITHUB_BASE_REF="$BASE_REF"
export AGENTIC_GATE_MODE="${AGENTIC_GATE_MODE:-advisory}"
export AGENTIC_TMP="${AGENTIC_TMP:-${REPO_ROOT}/.agentic-quality-gate/tmp}"
# Persistent Semgrep venv in user cache (no admin; reused across runs)
export AGENTIC_SEMGREP_PREFIX="${AGENTIC_SEMGREP_PREFIX:-${HOME}/.cache/agentic-quality-gate/semgrep-prefix}"
mkdir -p "$AGENTIC_TMP" "$(dirname "$AGENTIC_SEMGREP_PREFIX")"
# Clean job artifacts only — do not wipe the Semgrep cache
find "$AGENTIC_TMP" -mindepth 1 -maxdepth 1 ! -name 'semgrep-prefix' -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$AGENTIC_TMP"
echo '{"engines":{},"ok":true,"failed_engines":[]}' > "${AGENTIC_TMP}/engine-status.json"

CHANGED="${AGENTIC_TMP}/pr-changed-files.txt"
: > "$CHANGED"

ensure_origin_base() {
  local base="$1"
  local origin_base="origin/${base}"
  if ! git rev-parse --verify "$origin_base" >/dev/null 2>&1; then
    git fetch --no-tags --depth=1 origin "${base}:refs/remotes/origin/${base}" 2>/dev/null || true
  fi
}

list_diffs_vs_ref() {
  local ref="$1"
  git diff --name-only --diff-filter=ACMR "${ref}...HEAD" 2>/dev/null || true
  git diff --name-only --diff-filter=ACMR "$ref" 2>/dev/null || true
  git diff --cached --name-only --diff-filter=ACMR "$ref" 2>/dev/null || true
}

keep_existing_paths() {
  local tmp_keep
  tmp_keep="$(mktemp)"
  while IFS= read -r f; do
    [[ -z "$f" || ! -e "$f" ]] && continue
    echo "$f"
  done < "$CHANGED" > "$tmp_keep"
  mv "$tmp_keep" "$CHANGED"
}

write_changed_from_git() {
  local base="$1"
  local origin_base="origin/${base}"
  ensure_origin_base "$base"

  if [[ "$STAGED" == "true" ]]; then
    git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | sort -u > "$CHANGED" || true
  elif git rev-parse --verify "$origin_base" >/dev/null 2>&1; then
    list_diffs_vs_ref "$origin_base" | sort -u > "$CHANGED" || true
  elif git rev-parse --verify "$base" >/dev/null 2>&1; then
    list_diffs_vs_ref "$base" | sort -u > "$CHANGED" || true
  else
    {
      git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null || true
      git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true
    } | sort -u > "$CHANGED" || true
  fi
  keep_existing_paths
}

if [[ ${#FILES[@]} -gt 0 ]]; then
  for f in "${FILES[@]}"; do
    [[ -e "$f" ]] && echo "$f"
  done | sort -u > "$CHANGED"
else
  write_changed_from_git "$BASE_REF"
fi

COUNT=$(wc -l < "$CHANGED" | tr -d ' ')
agentic_log "═══ Local Quality Gate (pre-PR) ═══"
agentic_log "  Repo:     ${REPO_ROOT}"
agentic_log "  Hub:      ${PIPELINE_DIR}"
agentic_log "  Base:     ${BASE_REF}"
agentic_log "  Mode:     staged=${STAGED} strict=${STRICT}"
agentic_log "  Files:    ${COUNT}"
agentic_log "  Work dir: ${AGENTIC_TMP}"

if [[ "$COUNT" -eq 0 ]]; then
  agentic_log "  No files to scan — nothing to do."
  if [[ "$JSON_OUT" == "true" ]]; then
    echo '{"status":"pass","mode":"advisory","findings":[],"note":"no files"}'
  fi
  exit 0
fi

# New lines denominator for duplication %
NEW_LINES=0
if [[ "$STAGED" == "true" ]]; then
  NEW_LINES=$(git diff --cached --numstat 2>/dev/null | awk '{ add+=$1 } END { print add+0 }' || echo 0)
elif git rev-parse --verify "origin/${BASE_REF}" >/dev/null 2>&1; then
  NEW_LINES=$(git diff --numstat "origin/${BASE_REF}" 2>/dev/null | awk '{ add+=$1 } END { print add+0 }' || echo 0)
fi
export AGENTIC_FORCE_NEW_LINES="$NEW_LINES"

PKG_JSON="${AGENTIC_TMP}/quality-package.json"
python3 "${SCRIPT_DIR}/metrics/load-package.py" \
  "${PIPELINE_DIR}/config/quality-gate.yml" \
  "${PIPELINE_DIR}/config/packages" \
  "${PKG_JSON}"

SEMGREP_ON=$(jq -r '.semgrep_enabled // true' "$PKG_JSON")
DUP_ON=$(jq -r '.duplication // true' "$PKG_JSON")
COMPLEX_ON=$(jq -r '.complexity // true' "$PKG_JSON")

if [[ "$COMPLEX_ON" == "true" ]]; then
  export LIZARD_COMPLEXITY_THRESHOLD
  LIZARD_COMPLEXITY_THRESHOLD=$(jq -r '.complexity_threshold // 15' "$PKG_JSON")
fi
if [[ "$DUP_ON" == "true" ]]; then
  export JSCPD_MAX_PCT_NEW_CODE
  JSCPD_MAX_PCT_NEW_CODE=$(jq -r '.duplication_max_pct // 3' "$PKG_JSON")
fi

run_engine() {
  local name="$1"
  shift
  agentic_log ""
  agentic_log "→ ${name}"
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    local findings="${AGENTIC_TMP}/${name}-findings.json"
    case "$name" in
      semgrep) findings="${AGENTIC_TMP}/semgrep-findings.json" ;;
      jscpd) findings="${AGENTIC_TMP}/jscpd-findings.json" ;;
      lizard) findings="${AGENTIC_TMP}/lizard-findings.json" ;;
    esac
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

# Coverage is CI-only for local runs
echo '[]' > "${AGENTIC_TMP}/coverage-findings.json"
record_engine "coverage" "skipped" "local mode — coverage is CI-only"

set +e
bash "${SCRIPT_DIR}/apply-quality-gate.sh"
GATE_RC=$?
set -e

if engines_failed || [[ "$ENGINE_FAIL" -ne 0 ]]; then
  python3 - "${AGENTIC_TMP}/engine-status.json" "${AGENTIC_TMP}/quality-gate.md" \
    "${AGENTIC_TMP}/gate-result.json" <<'PY'
import json, sys
from pathlib import Path
status_path, md_path, gate_path = sys.argv[1:4]
status = json.loads(Path(status_path).read_text(encoding="utf-8"))
failed = status.get("failed_engines") or []
reasons = [f"- ❌ **Scanner {n} failed to run** — {((status.get('engines') or {}).get(n) or {}).get('reason') or 'unknown'}" for n in failed]
md = Path(md_path)
body = md.read_text(encoding="utf-8") if md.is_file() else ""
block = "#### Scanner failures (fail-closed)\n\n" + "\n".join(reasons) + "\n\n"
if "#### Scanner failures" not in body:
    if "#### Failed conditions" in body:
        body = body.replace("#### Failed conditions", block + "#### Failed conditions", 1)
    else:
        body = block + body
    md.write_text(body, encoding="utf-8")
if Path(gate_path).is_file():
    gate = json.loads(Path(gate_path).read_text(encoding="utf-8"))
    gate["status"] = "fail"
    gate["blocking"] = True
    gate["exit_code"] = 1
    Path(gate_path).write_text(json.dumps(gate, indent=2) + "\n", encoding="utf-8")
PY
fi

REPORT_ARGS=(--tmp "$AGENTIC_TMP")
if [[ "$JSON_OUT" == "true" ]]; then
  REPORT_ARGS+=(--json)
fi
python3 "${SCRIPT_DIR}/metrics/print-local-report.py" "${REPORT_ARGS[@]}"

STATUS=$(jq -r '.status // "n/a"' "${AGENTIC_TMP}/gate-result.json" 2>/dev/null || echo n/a)

if [[ "$STRICT" == "true" ]]; then
  if engines_failed || [[ "$ENGINE_FAIL" -ne 0 ]]; then
    exit 1
  fi
  if [[ "$STATUS" == "fail" || "$STATUS" == "warn" ]]; then
    exit 1
  fi
  exit 0
fi

# Advisory: always green for hooks/IDE unless --strict
exit 0
